// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IRandomNumberGenerator.sol";
import "./interfaces/IPancakeSwapLottery.sol";

/** @title PancakeSwap Lottery.
 * @notice It is a contract for a lottery system using
 * randomness provided externally.
 */
contract PancakeSwapLottery is ReentrancyGuard, IPancakeSwapLottery, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    address public injectorAddress;
    address public operatorAddress;
    address public treasuryAddress;

    uint256 public currentLotteryId;
    uint256 public currentTicketId;
    // track the winners
    uint256 public currentWinnerId;

    uint256 public currentRewardId;

    uint256 public maxNumberTicketsPerBuyOrClaim = 100;

    uint256 public maxPriceTicketInCake = 50 ether;
    uint256 public minPriceTicketInCake = 0.005 ether;

    uint256 public pendingInjectionNextLottery;

    uint256 public constant MIN_LENGTH_LOTTERY = 4 hours - 5 minutes; // 4 hours
    uint256 public constant MAX_LENGTH_LOTTERY = 4 days + 5 minutes; // 4 days
    uint256 public constant MAX_REFERRAL_FEE = 3000; // 30%

    IERC20 public cakeToken;
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
        uint256 priceTicketInCake;
        uint256 firstTicketId;
        uint256 firstTicketIdNextLottery;
        uint256 amountCollectedInCake;
        uint32 finalNumber;
        uint256 ticketsSold;
        uint256 minTicketsToSell;
        uint256 maxTicketsToSell;
        uint256[] prizes; // in eth
        uint256 referralReward; // 500: 5% // 200: 2% // 50: 0.5%
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

    // Mapping are cheaper than arrays
    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => Ticket) private _tickets;
    mapping(uint256 => Winners) public _winners;

    // Bracket calculator is used for verifying claims for ticket prizes
    mapping(uint32 => uint32) private _bracketCalculator;

    // Keeps track of number of ticket per unique combination for each lotteryId
    mapping(uint256 => mapping(uint32 => uint256)) private _numberTicketsPerLotteryId;

    // Keep track of user ticket ids for a given lotteryId
    mapping(address => mapping(uint256 => uint256[])) private _userTicketIdsPerLotteryId;

    // Keep track of ticket number for a given lotteryId
    mapping(uint256 => uint32[]) public _ticketsSold;

    // Keep track of ticket ids for a given lotteryId
    mapping(uint256 => uint256[]) public _ticketsIds;

    // Keep rewards to be distribute
    // mapping(uint256 => Rewards) private _rewards;
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
        uint256 priceTicketInCake,
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

    /**
     * @notice Constructor
     * @dev RandomNumberGenerator must be deployed prior to this contract
     * @param _cakeTokenAddress: address of the CAKE token
     * @param _randomGeneratorAddress: address of the RandomGenerator contract used to work with ChainLink VRF
     */
    constructor(address _cakeTokenAddress, address _randomGeneratorAddress) {
        cakeToken = IERC20(_cakeTokenAddress);
        randomGenerator = IRandomNumberGenerator(_randomGeneratorAddress);

        // Initializes a mapping
        _bracketCalculator[0] = 1;
        _bracketCalculator[1] = 11;
        _bracketCalculator[2] = 111;
        _bracketCalculator[3] = 1111;
        _bracketCalculator[4] = 11111;
        _bracketCalculator[5] = 111111;
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
        // require(address(msg.sender) != _referral, "Referral must be different than buyer");
        require(_ticketNumbers.length != 0, "No ticket specified");
        require(_ticketNumbers.length <= maxNumberTicketsPerBuyOrClaim, "Too many tickets");

        require(_lotteries[_lotteryId].status == Status.Open, "Lottery is not open");
        require(block.timestamp < _lotteries[_lotteryId].endTime, "Lottery is over");

        require(
            _lotteries[_lotteryId].ticketsSold <= _lotteries[_lotteryId].maxTicketsToSell,
            "Maximum number of lottery tickets exceeded"
        );

        // calculate if the tickets to buy does not exeed the max number of tickets in lottery
        uint256 tikectsSold = _lotteries[_lotteryId].ticketsSold.add(_ticketNumbers.length);
        require(tikectsSold <= _lotteries[_lotteryId].maxTicketsToSell, "Maximum number of lottery tickets exceeded");

        // Calculate number of CAKE to this contract
        uint256 amountCakeToTransfer = _lotteries[_lotteryId].priceTicketInCake.mul(_ticketNumbers.length);

        uint256 amountRewardToTransfer = _calculateRewards(
            _lotteries[_lotteryId].referralReward,
            _lotteries[_lotteryId].priceTicketInCake,
            _ticketNumbers.length
        );

        // Transfer cake tokens to this contract
        cakeToken.safeTransferFrom(address(msg.sender), address(this), amountCakeToTransfer);

        // only give a reward id _referral != msg.sender
        if (address(msg.sender) != _referral) {
            // Transfer cake tokens to referral address
            // cakeToken.transfer(_referral, amountRewardToTransfer);
            // store reward to distribute on lottery close
            _rewards[_referral][_lotteryId].push(Rewards({reward: amountRewardToTransfer,distributed: false}));
        }

        // Increment the total amount collected for the lottery round
        _lotteries[_lotteryId].amountCollectedInCake += amountCakeToTransfer;

        for (uint256 i = 0; i < _ticketNumbers.length; i++) {
            uint32 thisTicketNumber = _ticketNumbers[i];
            require((thisTicketNumber >= 1000000) && (thisTicketNumber <= 1999999), "Outside range");

            uint32[] memory alreadySold = getTickets(_lotteryId);
            // validate if ticket aready sold
            if (alreadySold.length != 0) {
                for (uint256 j = 0; j < alreadySold.length; j++) {
                    require((thisTicketNumber != alreadySold[j]), "Ticket already sold, choose another number and try it again.");
                }
            }

            // used in frontend
            _userTicketIdsPerLotteryId[msg.sender][_lotteryId].push(currentTicketId);

            _tickets[currentTicketId] = Ticket({number: thisTicketNumber, owner: msg.sender, status: true});

            // track ticket number sold
            _ticketsSold[_lotteryId].push(thisTicketNumber);
            // track tickets ids per lottery
            _ticketsIds[_lotteryId].push(currentTicketId);

            // Increase lottery ticket number
            currentTicketId++;

            // Increase ticketsSold
            _lotteries[_lotteryId].ticketsSold += 1;
        }

        emit TicketsPurchase(msg.sender, _lotteryId, _ticketNumbers.length);
    }

    /**
     * @notice validate if ticket number is already sold
     * @param _lotteryId: lotteryId
     * @dev Callable internally
     */
    function getTickets(uint256 _lotteryId) internal view returns(uint32[] memory) {
        uint256 length = _ticketsSold[_lotteryId].length;
        uint32[] memory ticketNumbers = new uint32[](length);

        for (uint256 i = 0; i < length; i++) {
            ticketNumbers[i] = _ticketsSold[_lotteryId][i];
        }

        return (ticketNumbers);
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
        require(block.timestamp > _lotteries[_lotteryId].endTime, "Lottery not over");

        // set firstTicketIdNextLottery
        _lotteries[_lotteryId].firstTicketIdNextLottery = currentTicketId;

        if (_lotteries[_lotteryId].ticketsSold >= _lotteries[_lotteryId].minTicketsToSell) {
            // Request a random number from the generator based on a seed
            randomGenerator.getRandomNumber(uint256(keccak256(abi.encodePacked(_lotteryId, currentTicketId))));
            _lotteries[_lotteryId].status = Status.Close;
        } else {
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

        // Initializes the rewardInCakeToTransfer
        uint256 rewardInCakeToTransfer;

        for (uint256 i = 0; i < _ticketNumbers.length; i++) {
            uint256 thisTicket = _ticketNumbers[i];

            uint256 length = currentWinnerId;
            uint256 rewardForTicket = 0;
            for (uint256 j = 0; j < length; j++) {
                if (
                    thisTicket == _winners[j].ticket &&
                    msg.sender == _winners[j].owner &&
                    _lotteryId == _winners[j].lotteryId &&
                    _winners[j].claimed == false
                ) {
                    rewardForTicket = _winners[j].prize;
                    _winners[j].claimed = true;
                }
            }

            // Increment the reward to transfer
            rewardInCakeToTransfer += rewardForTicket;
        }
        // Check user is claiming the correct bracket
        require(rewardInCakeToTransfer != 0, "No prize for this lottery");
        
        // Transfer money to msg.sender
        cakeToken.safeTransfer(msg.sender, rewardInCakeToTransfer);

        emit TicketsClaim(msg.sender, rewardInCakeToTransfer, _lotteryId, _ticketNumbers.length);
    }

    /**
     * @notice Claim a set of winning tickets for a lottery
     * @param _lotteryId: lottery id
     * @dev Callable by users only, not contract!
     */
    function withdrawFunds(
        uint256 _lotteryId
    ) external notContract nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Unrealized, "Lottery is claimable");

        // Initializes the rewardInCakeToTransfer
        uint256 amountToReturn;
        uint256 length = _ticketsIds[_lotteryId].length;

        for (uint256 i = 0; i < length; i++) {
            uint256 amount = 0;
            uint256 ticketId = _ticketsIds[_lotteryId][i];

            if (_tickets[ticketId].owner == msg.sender && _tickets[ticketId].status == true) {
                _tickets[ticketId].status = false;
                amount = _lotteries[_lotteryId].priceTicketInCake;
            }
            // Increment the reward to transfer
            amountToReturn += amount;
        }
        // Check if user have purchased tickets
        require(amountToReturn != 0, "No amount to return for this lottery");
        
        // Transfer money to msg.sender
        cakeToken.safeTransfer(msg.sender, amountToReturn);

        emit ReturnFunds(msg.sender, amountToReturn);
    }

    /*REMOVE*/
    function tickIds(uint256 _lotteryId) public view returns(uint256[] memory) {
        return _ticketsIds[_lotteryId];
    }

    /**
     * @notice shuffle index of the _ticketsIds
     * @param _lotteryId: lottery id
     * @param number: generated random number
     * @dev internal!
     */
    function shuffle(uint256 _lotteryId, uint256 number) public view returns(uint256[] memory) {
        uint256[] memory newArray = _ticketsIds[_lotteryId];
        for (uint256 i = 0; i < newArray.length; i++) {
            uint256 n = i + number % (newArray.length - i);
            uint256 temp = newArray[n];
            newArray[n] = newArray[i];
            newArray[i] = temp;
        }
        return newArray;
    }

    /*REMOVE*/
    function getRamd(uint256 prizesToGive) public view returns(uint256[] memory) {
        // Request a random number from the generator based on a seed
        // randomGenerator.getRandomNumber(uint256(keccak256(abi.encodePacked(_lotteryId, currentTicketId))));
        // get the generated number
        uint256 number = randomGenerator.viewRandomResult();
        // expand the numbers (randomNumber, numberToGenerate)
        uint256[] memory numbers = randomGenerator.expand(number, prizesToGive);
        return numbers;
        
    }

    function _winnerIndex(uint256 number, uint256 length) public pure returns(uint256) {
        return number % length - 1;
    }

    function drawAndMakeLotteryClaimable(uint256 _lotteryId)
        external
        onlyOperator
        nonReentrant
    {
        require(_lotteries[_lotteryId].status == Status.Close, "Lottery not close");
        require(_lotteryId == randomGenerator.viewLatestLotteryId(), "Numbers not drawn");

        // prizes to give per lottery
        uint256 prizesToGive = _lotteries[_lotteryId].prizes.length;
        // get the generated number
        uint32 number = randomGenerator.viewRandomResult();
        // expand the numbers (randomNumber, numberToGenerate)
        uint256[] memory numbers = randomGenerator.expand(number, prizesToGive);
        // total tickets sold per lottery
        uint256 length = _lotteries[_lotteryId].ticketsSold;

        // iterate to get the winners
        for (uint256 i = 0; i < prizesToGive; i++) {
            // get the index of the winner ticket
            uint256 winnerIndex = numbers[i] % length - 1;

            uint256[] memory suffletickets = shuffle(_lotteryId, winnerIndex);
            // get the id
            uint256 shuffleId = suffletickets[winnerIndex];
            // get the ticketId based on the shuffleId
            // not working in second lottery
            // uint256 ticket = _ticketsIds[_lotteryId][shuffleId];

            // store the winner to be able to claim the prize
            _winners[currentWinnerId] = Winners({
                lotteryId: _lotteryId,
                ticket: _tickets[shuffleId].number,
                prize: _lotteries[_lotteryId].prizes[i],
                owner: _tickets[shuffleId].owner,
                claimed: false
            });

            currentWinnerId++;
        }

        // Update internal statuses for lottery
        _lotteries[_lotteryId].finalNumber = number;
        _lotteries[_lotteryId].status = Status.Claimable;

        emit LotteryNumberDrawn(currentLotteryId, number, prizesToGive);
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
     * @param _amount: amount to inject in CAKE token
     * @dev Callable by owner or injector address
     */
    function injectFunds(uint256 _lotteryId, uint256 _amount) external override onlyOwnerOrInjector {
        require(_lotteries[_lotteryId].status == Status.Open, "Lottery not open");

        cakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
        _lotteries[_lotteryId].amountCollectedInCake += _amount;

        emit LotteryInjection(_lotteryId, _amount);
    }

    /**
     * @notice Start the lottery
     * @dev Callable by operator
     * @param _endTime: endTime of the lottery
     * @param _priceTicketInCake: price of a ticket in CAKE
     */
    function startLottery(
        uint256 _endTime,
        uint256 _priceTicketInCake,
        uint256 _minTicketsToSell,
        uint256 _maxTicketsToSell,
        uint256[] calldata _prizes,
        uint256 _referralReward
    ) external override onlyOperator {
        require(
            (currentLotteryId == 0) || 
            (_lotteries[currentLotteryId].status == Status.Claimable) ||
            (_lotteries[currentLotteryId].status == Status.Unrealized),
            "Not time to start lottery"
        );

        require(
            ((_endTime - block.timestamp) > MIN_LENGTH_LOTTERY) && ((_endTime - block.timestamp) < MAX_LENGTH_LOTTERY),
            "Lottery length outside of range"
        );

        require(
            (_priceTicketInCake >= minPriceTicketInCake) && (_priceTicketInCake <= maxPriceTicketInCake),
            "Outside of limits"
        );

        require(_referralReward <= MAX_REFERRAL_FEE, "Referral fee too high");

        currentLotteryId++;

        _lotteries[currentLotteryId] = Lottery({
            status: Status.Open,
            startTime: block.timestamp,
            endTime: _endTime,
            priceTicketInCake: _priceTicketInCake,
            firstTicketId: currentTicketId,
            firstTicketIdNextLottery: currentTicketId,
            amountCollectedInCake: pendingInjectionNextLottery,
            finalNumber: 0,
            ticketsSold: 0,
            minTicketsToSell: _minTicketsToSell,
            maxTicketsToSell: _maxTicketsToSell,
            prizes: _prizes,
            referralReward: _referralReward
        });

        emit LotteryOpen(
            currentLotteryId,
            block.timestamp,
            _endTime,
            _priceTicketInCake,
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
        require(_tokenAddress != address(cakeToken), "Cannot be CAKE token");

        IERC20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);

        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }

    /**
     * @notice Set CAKE price ticket upper/lower limit
     * @dev Only callable by owner
     * @param _minPriceTicketInCake: minimum price of a ticket in CAKE
     * @param _maxPriceTicketInCake: maximum price of a ticket in CAKE
     */
    function setMinAndMaxTicketPriceInCake(uint256 _minPriceTicketInCake, uint256 _maxPriceTicketInCake)
        external
        onlyOwner
    {
        require(_minPriceTicketInCake <= _maxPriceTicketInCake, "minPrice must be < maxPrice");

        minPriceTicketInCake = _minPriceTicketInCake;
        maxPriceTicketInCake = _maxPriceTicketInCake;
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
     * @notice View rewards for a given ticket, providing a bracket, and lottery id
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

        /*
        // Check ticketId is within range
        if (
            (_lotteries[_lotteryId].firstTicketIdNextLottery < _ticketNumber) &&
            (_lotteries[_lotteryId].firstTicketId >= _ticketNumber)
        ) {
            return 0;
        }
        */

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
        uint256 length = currentWinnerId;
        
        uint256 rewardForTicket = 0;

        for (uint256 i = 0; i < length; i++) {
            if (
                _ticketNumber == _winners[i].ticket &&
                msg.sender == _winners[i].owner &&
                _lotteryId == _winners[i].lotteryId &&
                _winners[i].claimed == false
            ) {
                rewardForTicket = _winners[i].prize;
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
     * @notice Return amount to user when lottery is not realized
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
        return (_priceTicket.mul(_numberTickets).mul(_referralReward).div(1e4));
    }

    /**
     * @notice Return amount to user when lottery is not realized
     * @param _lotteryId: lottery id
     * @dev Callable by users only, not contract!
     */
    function distributeReferralRewards(
        uint256 _lotteryId
    ) external notContract nonReentrant {
        require(_lotteries[_lotteryId].status == Status.Claimable, "Lottery not claimable");
        // Initializes the rewardInCakeToTransfer
        uint256 rewardInCakeToTransfer;

        uint256 records = _rewards[msg.sender][_lotteryId].length;

        for (uint256 i = 0; i < records; i++) {
            uint256 reward = 0;
            if (_rewards[msg.sender][_lotteryId][i].distributed == false) {
                _rewards[msg.sender][_lotteryId][i].distributed = true;
                reward = _rewards[msg.sender][_lotteryId][i].reward;
            }
            rewardInCakeToTransfer += reward;
        }

        require(rewardInCakeToTransfer != 0, "No rewards for this lottery");

        cakeToken.transfer(msg.sender, rewardInCakeToTransfer);
        emit DistributeRewards(msg.sender, rewardInCakeToTransfer);
    }
}
