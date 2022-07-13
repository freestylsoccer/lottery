// SPDX-License-Identifier: MIT
// wincket.com
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IRandomNumberGenerator.sol";
import "./interfaces/IWincketLottery.sol";

/** @title Wincket Lottery.
 * @notice It is a contract for a lottery system using
 * randomness provided by Chainlink VRF.
 */
contract WincketLottery is ReentrancyGuard, IWincketLottery, Ownable {
    using SafeERC20 for IERC20;

    address public injectorAddress;
    address public operatorAddress;
    address public treasuryAddress;

    uint256 public currentLotteryId;
    uint256 public currentTicketId;
    uint256 public currentWinnerId;

    uint256 public expandTo = 5;

    uint256 public maxNumberTicketsPerBuyOrClaim = 100;

    uint256 public maxPriceTicketInBusd = 50 ether;
    uint256 public minPriceTicketInBusd = 0.5 ether;

    uint256 public pendingInjectionNextLottery;

    uint256 public constant MIN_LENGTH_LOTTERY = 4 hours - 5 minutes; // 4 hours
    uint256 public constant MAX_LENGTH_LOTTERY = 100 days + 5 minutes; // 100 days
    uint256 public constant MAX_REFERRAL_FEE = 5000; // 50%

    IERC20 public busdToken; // BUSD Token
    IRandomNumberGenerator public randomGenerator;

    enum Status {
        Pending,
        Open,
        Close,
        Claimable,
        Unrealized
    }

    struct Lottery {
        Status status;
        uint256 startTime;
        uint256 endTime;
        uint256 priceTicketInBusd;
        uint256 firstTicketId;
        uint256 firstTicketIdNextLottery;
        uint256 amountCollectedInBusd;
        uint32 finalNumber;
        uint256 ticketsSold;
        uint256 minTicketsToSell;
        uint256 maxTicketsToSell;
        uint256[] prizes; // in eth
        uint256 referralReward; // 500: 5% // 200: 2% // 50: 0.5%
        uint256 firstWinnerId;
        uint256 firstWinnerIdNextLottery;
    }

    struct Ticket {
        uint32 number;
        address owner;
        bool status;
    }

    struct Winners {
        uint256 lotteryId;
        uint256 ticket;
        uint256 prize;
        address owner;
        bool claimed;
    }

    struct TicketsSold {
        uint256 lotteryId;
        uint32 number;
        address owner;
    }

    struct Rewards {
        uint256 reward;
        bool distributed;
    }

    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => Ticket) private _tickets;
    mapping(uint256 => Winners) public _winners;

    // Keep track of user ticket ids for a given lotteryId
    mapping(address => mapping(uint256 => uint256[])) private _userTicketIdsPerLotteryId;

    // Keep track of tickets ids sold for each lottery
    mapping(uint256 => mapping(uint256 => bool)) private _ticketsAlreadySols;

    // Rewards to be distributed
    mapping(address => mapping(uint256 => Rewards[])) private _rewards;

    modifier notContract() {
        require(!_isContract(msg.sender), "Contract not allowed");
        require(msg.sender == tx.origin, "Proxy contract not allowed");
        _;
    }

    modifier onlyOperator() {
        require(msg.sender == operatorAddress, "Not operator");
        _;
    }

    modifier onlyOwnerOrInjector() {
        require((msg.sender == owner()) || (msg.sender == injectorAddress), "Not owner or injector");
        _;
    }

    event AdminTokenRecovery(address token, uint256 amount);
    event LotteryClose(uint256 indexed lotteryId, uint256 firstTicketIdNextLottery);
    event LotteryInjection(uint256 indexed lotteryId, uint256 injectedAmount);
    event LotteryOpen(
        uint256 indexed lotteryId,
        uint256 startTime,
        uint256 endTime,
        uint256 priceTicketInBusd,
        uint256 firstTicketId,
        uint256 injectedAmount
    );
    event LotteryNumberDrawn(uint256 indexed lotteryId, uint256 finalNumber, uint256 countWinningTickets);
    event NewOperatorAndTreasuryAndInjectorAddresses(address operator, address treasury, address injector);
    event NewRandomGenerator(address indexed randomGenerator);
    event TicketsPurchase(address indexed buyer, uint256 indexed lotteryId, uint256 numberTickets);
    event TicketsClaim(address indexed claimer, uint256 amount, uint256 indexed lotteryId, uint256 numberTickets);
    event DistributeRewards(address claimer, uint256 amount);
    event ReturnFunds(address owner, uint256 amount);
    event NewExpandTo(uint256 number);

    /**
     * @notice Constructor
     * @dev RandomNumberGenerator must be deployed prior to this contract
     * @param _busdTokenAddress: address of the BUSD token
     * @param _randomGeneratorAddress: address of the RandomGenerator contract used to work with ChainLink VRF
     */
    constructor(address _busdTokenAddress, address _randomGeneratorAddress) {
        busdToken = IERC20(_busdTokenAddress);
        randomGenerator = IRandomNumberGenerator(_randomGeneratorAddress);
    }

    /**
     * @notice Buy tickets for the current lottery
     * @param _lotteryId: lotteryId
     * @param _ticketNumbers: array of ticket numbers between 1,000,000 and 1,999,999
     * @dev Callable by users
     */
    function buyTickets(uint256 _lotteryId, uint32[] calldata _ticketNumbers, address _referral)
        external
        override
        notContract
        nonReentrant
    {
        require(_ticketNumbers.length != 0, "No ticket specified");
        require(_ticketNumbers.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");

        require(_lotteries[_lotteryId].status == Status.Open, "Lottery is not open");
        require(block.timestamp < _lotteries[_lotteryId].endTime, "Lottery is over");

        require(_lotteries[_lotteryId].ticketsSold <= _lotteries[_lotteryId].maxTicketsToSell,
            "Maximum number of lottery tickets to sell exceeded"
        );

        // calculate if the tickets to buy does not exeed the max number of tickets in lottery
        uint256 ticketsSold = _lotteries[_lotteryId].ticketsSold + _ticketNumbers.length;
        require(ticketsSold <= _lotteries[_lotteryId].maxTicketsToSell,
            "The number of tickets to buy exceeds the maximum number of tickets available"
        );

        uint256 amountBusdToTransfer = _lotteries[_lotteryId].priceTicketInBusd * _ticketNumbers.length;

        uint256 rewardsAmountToTransfer = _calculateRewards(
            _lotteries[_lotteryId].referralReward,
            _lotteries[_lotteryId].priceTicketInBusd,
            _ticketNumbers.length
        );

        busdToken.safeTransferFrom(address(msg.sender), address(this), amountBusdToTransfer);

        // Referral must be different than msg.sender
        if (address(msg.sender) != _referral) {
            // Save reward to distribute at lottery close
            _rewards[_referral][_lotteryId].push(
                Rewards({
                    reward: rewardsAmountToTransfer,
                    distributed: false
                })
            );
        }

        // Increment the total amount collected for the lottery round
        _lotteries[_lotteryId].amountCollectedInBusd += amountBusdToTransfer;

        for (uint256 i = 0; i < _ticketNumbers.length; i++) {
            uint32 thisTicketNumber = _ticketNumbers[i];
            require((thisTicketNumber >= 1000000) && (thisTicketNumber <= 1999999), "Outside range");
            require(!_ticketsAlreadySols[_lotteryId][thisTicketNumber],
                "Ticket already sold, choose another number and try it again."
            );

            _ticketsAlreadySols[_lotteryId][thisTicketNumber] =  true;

            _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(currentTicketId);

            _tickets[currentTicketId] = Ticket({number: thisTicketNumber, owner: msg.sender, status: true});

            // Increase lottery ticket number
            currentTicketId++;

            // Increase tickets sold number
            _lotteries[_lotteryId].ticketsSold += 1;
        }

        emit TicketsPurchase(msg.sender, _lotteryId, _ticketNumbers.length);
    }

    /**
     * @notice Close lottery
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function closeLottery(uint256 _lotteryId)
        external
        override
        onlyOperator
        nonReentrant
    {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");
        require(block.timestamp > _lotteries[_lotteryId].endTime ||
            _lotteries[_lotteryId].ticketsSold == _lotteries[_lotteryId].maxTicketsToSell,
            "Lottery not over"
        );

        // set first ticketId for the next lottery
        _lotteries[_lotteryId].firstTicketIdNextLottery = currentTicketId;
        // set lottery end time
        // used when the number of tickets to be sold is reached before the closing date established for the lottery.
        _lotteries[_lotteryId].endTime = block.timestamp;

        if (_lotteries[_lotteryId].ticketsSold >= _lotteries[_lotteryId].minTicketsToSell) {
            // Request a random number from the generator based on a seed
            randomGenerator.getRandomNumber(uint256(keccak256(abi.encodePacked(_lotteryId, currentTicketId))));
            _lotteries[_lotteryId].status = Status.Close;
        } else {
            // set lottery.status = unrealized, when the minimum number of tickets to sell is not reached
            _lotteries[_lotteryId].status = Status.Unrealized;
        }

        emit LotteryClose(_lotteryId, currentTicketId);
    }

    /**
     * @notice Claim a set of winning tickets for a lottery
     * @param _lotteryId: lottery id
     * @param _ticketNumbers: array of ticket numbers
     * @dev Callable by users only, not contract!
     */
    function claimTickets(
        uint256 _lotteryId,
        uint256[] calldata _ticketNumbers
    ) external override notContract nonReentrant {
        require(_ticketNumbers.length != 0, "Length must be >0");
        require(_ticketNumbers.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");
        require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");

        // Initializes the rewardInBusdToTransfer
        uint256 rewardInBusdToTransfer;
        
        // first winner id in lottery
        uint256 _firstWinnerId = _lotteries[_lotteryId].firstWinnerId;
        // winners in lottery
        uint256 length = _lotteries[_lotteryId].prizes.length;

        for (uint256 i = 0; i < _ticketNumbers.length; i++) {
            uint256 thisTicket = _ticketNumbers[i];

            uint256 rewardForTicket = 0;
            for (uint256 j = 0; j < length; j++) {
                if (
                    thisTicket == _winners[_firstWinnerId + j].ticket &&
                    msg.sender == _winners[_firstWinnerId + j].owner &&
                    _lotteryId == _winners[_firstWinnerId + j].lotteryId &&
                    _winners[_firstWinnerId + j].claimed == false
                ) {
                    rewardForTicket = _winners[_firstWinnerId + j].prize;
                    _winners[_firstWinnerId + j].claimed = true;
                }
            }

            // Increment the reward to transfer
            rewardInBusdToTransfer += rewardForTicket;
        }
        // Check if user has rewards
        require(rewardInBusdToTransfer != 0, "No prize for this lottery");
        
        // Transfer money to msg.sender
        busdToken.safeTransfer(msg.sender, rewardInBusdToTransfer);

        emit TicketsClaim(msg.sender, rewardInBusdToTransfer, _lotteryId, _ticketNumbers.length);
    }    

    /**
     * @notice Claim a set of tickets for an unrealized lottery
     * @param _lotteryId: lottery id
     * @dev Callable by users only, not contract!
     */
    function withdrawFunds(
        uint256 _lotteryId
    ) external notContract nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Unrealized, "Lottery != unrealized");

        uint256 amountToReturn = 0;
        uint256 length = _userTicketIdsPerLotteryId[msg.sender][_lotteryId].length;

        for (uint256 i = 0; i < length; i++) {
            uint256 amount = 0;
            uint256 ticketId = _userTicketIdsPerLotteryId[msg.sender][_lotteryId][i];

            if (_tickets[ticketId].owner == msg.sender && _tickets[ticketId].status == true) {
                _tickets[ticketId].status = false;
                amount = _lotteries[_lotteryId].priceTicketInBusd;
            }
            // Increment the amount to return
            amountToReturn += amount;
        }
        // Check if the user has bought tickets
        require(amountToReturn > 0, "No amount to return for this lottery");
        
        // Transfer money to msg.sender
        busdToken.safeTransfer(msg.sender, amountToReturn);

        emit ReturnFunds(msg.sender, amountToReturn);
    }

    /**
     * @notice Randomly order the id of the array of tickets sold in the lottery
     * @param _lotteryTickets: tickets array
     * @param numbers: generated random numbers
     * @dev internal!
     */
    function shuffle(uint256[] memory _lotteryTickets, uint256[] memory numbers) internal pure returns(uint256[] memory) {
        for (uint256 k = 0; k < numbers.length; k++) {
            for (uint256 i = 0; i < _lotteryTickets.length; i++) {
                uint256 n = i + numbers[0] % (_lotteryTickets.length - i);
                uint256 temp = _lotteryTickets[n];
                _lotteryTickets[n] = _lotteryTickets[i];
                _lotteryTickets[i] = temp;
            }
        }
        return _lotteryTickets;
    }

    /**
     * @notice Create a memory copy of the array of tickets sold in the lottery
     * @param _lotteryId: lottery id
     * @dev internal!
     */
    function getTicketsIds(uint256 _lotteryId) internal view returns(uint256[] memory) {
        uint256 firstTicketId = _lotteries[_lotteryId].firstTicketId;
        uint256 firstTicketIdNextLottery = _lotteries[_lotteryId].firstTicketIdNextLottery;

        uint256 length = firstTicketIdNextLottery - firstTicketId;
        uint256[] memory newArray = new uint256[](length);
        uint256 j = 0;
        for (uint256 i = firstTicketId; i < firstTicketIdNextLottery; i++) {
            newArray[j] = i;
            j++;
        }

        return newArray;
    }

    /**
     * @notice Get winning tickets and make lottery claimable
     * @param _lotteryId: lottery id
     * @dev Callable by operator
     */
    function drawAndMakeLotteryClaimable(uint256 _lotteryId)
        external
        onlyOperator
        nonReentrant
    {
        require(_lotteries[_lotteryId].status == Status.Close, "Lottery not close");
        require(_lotteryId == randomGenerator.viewLatestLotteryId(), "Numbers not drawn");

        // Initializes the amount to transfer to treasury
        uint256 amountToTransferToTreasury;
        // Initialize prizes amount
        uint256 _totalPrizeAmount = 0;

        // get the generated random number
        uint32 number = randomGenerator.viewRandomResult();
        // expand the numbers (randomNumber, numberToGenerate)
        uint256[] memory numbers = randomGenerator.expand(number, expandTo);
        // tickets sold per lottery
        uint256[] memory lotteryTickets = getTicketsIds(_lotteryId);
        uint256[] memory shuffledtickets = shuffle(lotteryTickets, numbers);
        // iterate to get the winners
        for (uint256 i = 0; i < _lotteries[_lotteryId].prizes.length; i++) {
            // get the id
            uint256 shuffledId = shuffledtickets[i];

            _totalPrizeAmount += _lotteries[_lotteryId].prizes[i];

            // store the winner to be able to claim the prize
            _winners[currentWinnerId] = Winners({
                lotteryId: _lotteryId,
                ticket: _tickets[shuffledId].number,
                prize: _lotteries[_lotteryId].prizes[i],
                owner: _tickets[shuffledId].owner,
                claimed: false
            });

            currentWinnerId++;
        }

        // Update internal statuses for lottery
        _lotteries[_lotteryId].finalNumber = number;
        _lotteries[_lotteryId].status = Status.Claimable;
        _lotteries[_lotteryId].firstWinnerIdNextLottery = currentWinnerId;

        uint256 referralFees = ((_lotteries[_lotteryId].ticketsSold * _lotteries[_lotteryId].priceTicketInBusd)
            * _lotteries[_lotteryId].referralReward) / 1e4;
        
        amountToTransferToTreasury = _lotteries[_lotteryId].amountCollectedInBusd - _totalPrizeAmount - referralFees;
        busdToken.safeTransfer(treasuryAddress, amountToTransferToTreasury);

        emit LotteryNumberDrawn(currentLotteryId, number, _lotteries[_lotteryId].prizes.length);
    }

    /**
     * @notice Change the random generator
     * @dev The calls to functions are used to verify the new generator implements them properly.
     * It is necessary to wait for the VRF response before starting a round.
     * Callable only by the contract owner
     * @param _randomGeneratorAddress: address of the random generator
     */
    function changeRandomGenerator(address _randomGeneratorAddress) external onlyOwner {
        require(
            (currentLotteryId == 0) || (_lotteries[currentLotteryId].status == Status.Claimable),
            "Lottery not in claimable"
        );

        // Request a random number from the generator based on a seed
        IRandomNumberGenerator(_randomGeneratorAddress).getRandomNumber(
            uint256(keccak256(abi.encodePacked(currentLotteryId, currentTicketId)))
        );

        // Calculate the finalNumber based on the randomResult generated by ChainLink's fallback
        IRandomNumberGenerator(_randomGeneratorAddress).viewRandomResult();

        randomGenerator = IRandomNumberGenerator(_randomGeneratorAddress);

        emit NewRandomGenerator(_randomGeneratorAddress);
    }

    /**
     * @notice Inject funds
     * @param _lotteryId: lottery id
     * @param _amount: amount to inject in BUSD token
     * @dev Callable by owner or injector address
     */
    function injectFunds(uint256 _lotteryId, uint256 _amount) external override onlyOwnerOrInjector {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");

        busdToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        _lotteries[_lotteryId].amountCollectedInBusd += _amount;

        emit LotteryInjection(_lotteryId, _amount);
    }

    /**
     * @notice Start the lottery
     * @dev Callable by operator
     * @param _endTime: endTime of the lottery
     * @param _priceTicketInBusd: price of a ticket in BUSD
     * @param _minTicketsToSell: Minimum number of tickets to be sold for the lottery
     * @param _maxTicketsToSell: Maximum number of tickets to be sold for the lottery
     * @param _prizes: [] prizes
     * @param _referralReward: referral rewards for the lottery
     */
    function startLottery(
        uint256 _endTime,
        uint256 _priceTicketInBusd,
        uint256 _minTicketsToSell,
        uint256 _maxTicketsToSell,
        uint256[] calldata _prizes,
        uint256 _referralReward
    ) external override onlyOperator {
        require(
            (currentLotteryId == 0) || (_lotteries[currentLotteryId].status == Status.Claimable) || (_lotteries[currentLotteryId].status == Status.Unrealized),
            "Not time to start lottery"
        );

        require(
            ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) && ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
            "Lottery length outside of range"
        );

        require(
            (_priceTicketInBusd >= minPriceTicketInBusd) && (_priceTicketInBusd <= maxPriceTicketInBusd),
            "Outside of limits"
        );

        require(_referralReward <= MAX_REFERRAL_FEE, "Referral fee too high");

        currentLotteryId++;

        _lotteries[currentLotteryId] = Lottery({
            status: Status.Open,
            startTime: block.timestamp,
            endTime: _endTime,
            priceTicketInBusd: _priceTicketInBusd,
            firstTicketId: currentTicketId,
            firstTicketIdNextLottery: currentTicketId,
            amountCollectedInBusd: pendingInjectionNextLottery,
            finalNumber: 0,
            ticketsSold: 0,
            minTicketsToSell: _minTicketsToSell,
            maxTicketsToSell: _maxTicketsToSell,
            prizes: _prizes,
            referralReward: _referralReward,
            firstWinnerId: currentWinnerId,
            firstWinnerIdNextLottery: currentWinnerId
        });

        emit LotteryOpen(
            currentLotteryId,
            block.timestamp,
            _endTime,
            _priceTicketInBusd,
            currentTicketId,
            pendingInjectionNextLottery
        );

        pendingInjectionNextLottery = 0;
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _tokenAddress: the address of the token to withdraw
     * @param _tokenAmount: the number of token amount to withdraw
     * @dev Only callable by owner.
     */
    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        require(_tokenAddress != address(busdToken), "Cannot be BUSD token");

        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /**
     * @notice Set BUSD price ticket upper/lower limit
     * @dev Only callable by owner
     * @param _minPriceTicketInBusd: minimum price of a ticket in BUSD
     * @param _maxPriceTicketInBusd: maximum price of a ticket in BUSD
     */
    function setMinAndMaxTicketPriceInBusd(uint256 _minPriceTicketInBusd, uint256 _maxPriceTicketInBusd)
        external
        onlyOwner
    {
        require(_minPriceTicketInBusd <= _maxPriceTicketInBusd, "minPrice must be < maxPrice");

        minPriceTicketInBusd = _minPriceTicketInBusd;
        maxPriceTicketInBusd = _maxPriceTicketInBusd;
    }

    /**
     * @notice Set max number of tickets
     * @dev Only callable by owner
     */
    function setMaxNumberTicketsPerBuy(uint256 _maxNumberTicketsPerBuy) external onlyOwner {
        require(_maxNumberTicketsPerBuy != 0, "Must be > 0");
        maxNumberTicketsPerBuyOrClaim = _maxNumberTicketsPerBuy;
    }

    /**
     * @notice Set operator, treasury, and injector addresses
     * @dev Only callable by owner
     * @param _operatorAddress: address of the operator
     * @param _treasuryAddress: address of the treasury
     * @param _injectorAddress: address of the injector
     */
    function setOperatorAndTreasuryAndInjectorAddresses(
        address _operatorAddress,
        address _treasuryAddress,
        address _injectorAddress
    ) external onlyOwner {
        require(_operatorAddress != address(0), "Cannot be zero address");
        require(_treasuryAddress != address(0), "Cannot be zero address");
        require(_injectorAddress != address(0), "Cannot be zero address");

        operatorAddress = _operatorAddress;
        treasuryAddress = _treasuryAddress;
        injectorAddress = _injectorAddress;

        emit NewOperatorAndTreasuryAndInjectorAddresses(_operatorAddress, _treasuryAddress, _injectorAddress);
    }

    /**
     * @notice Set new expand to number
     * @dev Only callable by owner
     * @param _number: new number to expand
     */
    function setExpandTo(uint256 _number) external onlyOwner {
        expandTo = _number;
        emit NewExpandTo(_number);
    }

    /**
     * @notice View current lottery id
     */
    function viewCurrentLotteryId() external view override returns (uint256) {
        return currentLotteryId;
    }

    /**
     * @notice View lottery information
     * @param _lotteryId: lottery id
     */
    function viewLottery(uint256 _lotteryId) external view returns (Lottery memory) {
        return _lotteries[_lotteryId];
    }

    /**
     * @notice View ticker statuses and numbers for an array of ticket ids
     * @param _ticketIds: array of _ticketId
     */
    function viewNumbersAndStatusesForTicketIds(uint256[] calldata _ticketIds)
        external
        view
        returns (uint32[] memory, bool[] memory)
    {
        uint256 length = _ticketIds.length;
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            ticketNumbers[i] = _tickets[_ticketIds[i]].number;
            if (_tickets[_ticketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                ticketStatuses[i] = false;
            }
        }

        return (ticketNumbers, ticketStatuses);
    }

    /**
     * @notice View rewards for a given ticket, providing a ticket number, and lottery id
     * @dev Computations are mostly offchain. This is used to verify a ticket!
     * @param _lotteryId: lottery id
     * @param _ticketNumber: ticket number
     */
    function viewRewardsForTicketNumber(
        uint256 _lotteryId,
        uint256 _ticketNumber
    ) external view returns (uint256) {
        // Check lottery is in claimable status
        if (_lotteries[_lotteryId].status != Status.Claimable) {
            return 0;
        }

        // Check ticketId is within range
        if (
            (_lotteries[_lotteryId].firstTicketIdNextLottery < _ticketNumber) &&
            (_lotteries[_lotteryId].firstTicketId >= _ticketNumber)
        ) {
            return 0;
        }

        return _getRewardsForTicketNumber(_lotteryId, _ticketNumber);
    }

    /**
     * @notice View user ticket ids, numbers, and statuses of user for a given lottery
     * @param _user: user address
     * @param _lotteryId: lottery id
     * @param _cursor: cursor to start where to retrieve the tickets
     * @param _size: the number of tickets to retrieve
     */
    function viewUserInfoForLotteryId(
        address _user,
        uint256 _lotteryId,
        uint256 _cursor,
        uint256 _size
    )
        external
        view
        override
        returns (
            uint256[] memory,
            uint32[] memory,
            bool[] memory,
            uint256
        )
    {
        uint256 length = _size;
        uint256 numberTicketsBoughtAtLotteryId = _userTicketIdsPerLotteryId[_user][_lotteryId].length;

        if (length > (numberTicketsBoughtAtLotteryId - _cursor)) {
            length = numberTicketsBoughtAtLotteryId - _cursor;
        }

        uint256[] memory lotteryTicketIds = new uint256[](length);
        uint32[] memory ticketNumbers = new uint32[](length);
        bool[] memory ticketStatuses = new bool[](length);

        for (uint256 i = 0; i < length; i++) {
            lotteryTicketIds[i] = _userTicketIdsPerLotteryId[_user][_lotteryId][i + _cursor];
            ticketNumbers[i] = _tickets[lotteryTicketIds[i]].number;

            // True = ticket claimed
            if (_tickets[lotteryTicketIds[i]].owner == address(0)) {
                ticketStatuses[i] = true;
            } else {
                // ticket not claimed (includes the ones that cannot be claimed)
                ticketStatuses[i] = false;
            }
        }

        return (lotteryTicketIds, ticketNumbers, ticketStatuses, _cursor + length);
    }

    /**
     * @notice Calculate rewards for a given ticket
     * @param _lotteryId: lottery id
     * @param _ticketNumber: ticket number
     */
    function _getRewardsForTicketNumber(
        uint256 _lotteryId,
        uint256 _ticketNumber
    ) internal view returns (uint256) {
        // first winner id in lottery
        uint256 _firstWinnerId = _lotteries[_lotteryId].firstWinnerId;
        // winners in lottery
        uint256 length = _lotteries[_lotteryId].prizes.length;
        
        uint256 rewardForTicket = 0;

        for (uint256 i = 0; i < length; i++) {
            if (
                _ticketNumber == _winners[_firstWinnerId + i].ticket &&
                msg.sender == _winners[_firstWinnerId + i].owner &&
                _lotteryId == _winners[_firstWinnerId + i].lotteryId &&
                _winners[_firstWinnerId + i].claimed == false
            ) {
                rewardForTicket = _winners[_firstWinnerId + i].prize;
            }
        }

        return rewardForTicket;
    }

    /**
     * @notice Check if an address is a contract
     */
    function _isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /**
     * @notice Calculate referral reward amount
     * @param _referralReward: address
     * @param _priceTicket: ticket price
     * @param _numberTickets: number of tickets
     * @dev Callable by users only, not contract!
     */
    function _calculateRewards(
        uint256 _referralReward,
        uint256 _priceTicket,
        uint256 _numberTickets
    ) internal pure returns (uint256) {
        return ((_priceTicket * _numberTickets * _referralReward) / 1e4);
    }

    /**
     * @notice Distribute referral reward amount
     * @param _lotteryId: lottery id
     * @dev Callable by users only, not contract!
     */
    function distributeReferralRewards(
        uint256 _lotteryId
    ) external notContract nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");
        // Initializes the rewardInBusdToTransfer
        uint256 rewardInBusdToTransfer = 0;

        uint256 records = _rewards[msg.sender][_lotteryId].length;

        for (uint256 i = 0; i < records; i++) {
            uint256 reward = 0;
            if (_rewards[msg.sender][_lotteryId][i].distributed == false) {
                _rewards[msg.sender][_lotteryId][i].distributed = true;
                reward = _rewards[msg.sender][_lotteryId][i].reward;
            }
            rewardInBusdToTransfer += reward;
        }

        require(rewardInBusdToTransfer > 0, "No rewards for this lottery");

        busdToken.transfer(msg.sender, rewardInBusdToTransfer);
        emit DistributeRewards(msg.sender, rewardInBusdToTransfer);
    }

    //-------------------------------- UI Data Provider --------------------------------//

    function getWinningTickets() external view returns(Winners[] memory) {
        Winners[] memory winningTickets = new Winners[](currentWinnerId);

        for (uint256 j = 0; j < currentWinnerId; j++) {
            winningTickets[j] = _winners[j];
        }

        return winningTickets;
    }

    function getWinningTicketsPerLotteryId(uint256 _lotteryId) external view returns(Winners[] memory) {
        // first winner id in lottery
        uint256 _firstWinnerId = _lotteries[_lotteryId].firstWinnerId;
        // winners in lottery
        uint256 length = _lotteries[_lotteryId].prizes.length;
        
        Winners[] memory winningTickets = new Winners[](length);

        for (uint256 i = 0; i < length; i++) {
            winningTickets[i] = _winners[_firstWinnerId + i];
        }

        return winningTickets;
    }

    /**
     * @notice Validate if the user has an outstanding amount to withdraw in a lottery not carried out
     * @param _lotteryId: lottery id
     * @param user: user
     * @dev Callable by users only, not contract!
     * @dev Used by frontend
     */
    function hasAmountToWithdraw(
        uint256 _lotteryId,
        address user
    ) public view returns(uint256, uint256) {
        require(_lotteries[_lotteryId].status == Status.Unrealized, "Lottery status != unrealized");

        uint256 amountToReturn = 0;
        uint256 length = _userTicketIdsPerLotteryId[user][_lotteryId].length;
        uint256 tickets = 0;
        for (uint256 i = 0; i < length; i++) {
            uint256 amount = 0;
            uint256 ticketId = _userTicketIdsPerLotteryId[user][_lotteryId][i];

            if (_tickets[ticketId].owner == user && _tickets[ticketId].status == true) {
                amount = _lotteries[_lotteryId].priceTicketInBusd;
                tickets += 1;
            }
            // Increment the amount to return
            amountToReturn += amount;
        }

        return (tickets, amountToReturn);
    }

    /**
     * @notice Validate if user has referral amount to claim
     * @param _lotteryId: lottery id
     * @param user: user
     * @dev Callable by users only, not contract!
     */
    function hasReferralRewardsToClaim(
        uint256 _lotteryId,
        address user
    ) public view returns(uint256) {
        require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");

        uint256 referralRewardToTransfer = 0;

        uint256 records = _rewards[user][_lotteryId].length;

        for (uint256 i = 0; i < records; i++) {
            uint256 reward = 0;
            if (_rewards[user][_lotteryId][i].distributed == false) {
                reward = _rewards[user][_lotteryId][i].reward;
            }
            referralRewardToTransfer += reward;
        }

        return referralRewardToTransfer;
    }
}
