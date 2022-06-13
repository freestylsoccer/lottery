
const { expect } = require("chai");
const { artifacts, contract } = require("hardhat");
const { parseEther } = require("ethers/lib/utils");
const { BN, constants, expectEvent, expectRevert, time } = require("@openzeppelin/test-helpers");

const MockERC20 = artifacts.require("./utils/MockERC20.sol");
const MockRandomNumberGenerator = artifacts.require("./utils/MockRandomNumberGenerator.sol");
const PancakeSwapLottery = artifacts.require("./PancakeSwapLottery.sol");

const PRICE_BNB = 400;

function gasToBNB(gas, gwei) {
  const num = gas * gwei * 10 ** -9;
  return num.toFixed(4);
}

function gasToUSD(gas, gwei, priceBNB) {
  const num = gas * priceBNB * gwei * 10 ** -9;
  return num.toFixed(2);
}

contract("Lottery V2", ([alice, bob, carol, david, erin, operator, treasury, injector]) => {
  // VARIABLES
  const _totalInitSupply = parseEther("10000");

  let _lengthLottery = new BN("14400"); // 4h
  let _priceTicketInBusd = parseEther("0.5");
  let _discountDivisor = "0";

  let _rewardsBreakdown = ["200", "300", "500", "1500", "2500", "5000"];
  let _treasuryFee = "0";
  let _minTicketsToSell = "100";
  let _maxTicketsToSell = "40000";
  let _prizes = [parseEther("100000"), parseEther("80000"), parseEther("50000")];
  let _referralReward = "500";

  let _rewardsAddress = injector;

  // Contracts
  let lottery, mockCake, randomNumberGenerator;

  // Generic variables
  let result;
  let endTime;

  before(async () => {
    // Deploy MockCake
    mockCake = await MockERC20.new("Mock CAKE", "CAKE", _totalInitSupply);

    // Deploy MockRandomNumberGenerator
    randomNumberGenerator = await MockRandomNumberGenerator.new({ from: alice });

    // Deploy PancakeSwapLottery
    lottery = await PancakeSwapLottery.new(mockCake.address, randomNumberGenerator.address, { from: alice });

    await randomNumberGenerator.setLotteryAddress(lottery.address, { from: alice });
  });

  describe("LOTTERY #1 - CUSTOM RANDOMNESS", async () => {
    it("Admin sets up treasury/operator address", async () => {
      result = await lottery.setOperatorAndTreasuryAndInjectorAddresses(operator, treasury, injector, { from: alice });
      expectEvent(result, "NewOperatorAndTreasuryAndInjectorAddresses", {
        operator: operator,
        treasury: treasury,
        injector: injector,
      });
    });

    it("Users mint and approve CAKE to be used in the lottery", async () => {
      for (let thisUser of [alice, bob, carol, david, erin]) {
        await mockCake.mintTokens(parseEther("1000000"), { from: thisUser });
        await mockCake.approve(lottery.address, parseEther("1000000000000000"), {
          from: thisUser,
        });
      }
    });

    it("Operator starts lottery", async () => {
      endTime = new BN(await time.latest()).add(_lengthLottery);

      result = await lottery.startLottery(
        endTime,
        _priceTicketInBusd,
        _minTicketsToSell,
        _maxTicketsToSell,
        _prizes,
        _referralReward,
        { from: operator }
      );

      expectEvent(result, "LotteryOpen", {
        lotteryId: "1",
        startTime: (await time.latest()).toString(),
        endTime: endTime.toString(),
        priceTicketInBusd: _priceTicketInBusd.toString(),
        firstTicketId: "0",
        injectedAmount: "0",
      });

      console.info(
        `        --> Cost to start the lottery: ${result.receipt.gasUsed}`
      );
    });

    it("Bob buys 100 tickets", async () => {
      const _ticketsBought = [
        "1000000",
        "1234562",
        "1234563",
        "1234564",
        "1234565",
        "1234566",
        "1234567",
        "1234568",
        "1234569",
        "1234570",
        "1334571",
        "1334572",
        "1334573",
        "1334574",
        "1334575",
        "1334576",
        "1334577",
        "1334578",
        "1334579",
        "1334580",
        "1434581",
        "1434582",
        "1434583",
        "1434584",
        "1434585",
        "1434586",
        "1434587",
        "1434588",
        "1434589",
        "1534590",
        "1534591",
        "1534592",
        "1534593",
        "1534594",
        "1534595",
        "1534596",
        "1534597",
        "1534598",
        "1534599",
        "1634600",
        "1634601",
        "1634602",
        "1634603",
        "1634604",
        "1634605",
        "1634606",
        "1634607",
        "1634608",
        "1634609",
        "1634610",
        "1634611",
        "1634612",
        "1634613",
        "1634614",
        "1634615",
        "1634616",
        "1634617",
        "1634618",
        "1634619",
        "1634620",
        "1634621",
        "1634622",
        "1634623",
        "1634624",
        "1634625",
        "1634626",
        "1634627",
        "1634628",
        "1634629",
        "1634630",
        "1634631",
        "1634632",
        "1634633",
        "1634634",
        "1634635",
        "1634636",
        "1634637",
        "1634638",
        "1634639",
        "1634640",
        "1634641",
        "1634642",
        "1634643",
        "1634644",
        "1634645",
        "1634646",
        "1634647",
        "1634648",
        "1634649",
        "1634650",
        "1634651",
        "1634652",
        "1634653",
        "1634654",
        "1634655",
        "1634656",
        "1634657",
        "1634658",
        "1634659",
        "1634660",
      ];

      result = await lottery.buyTickets("1", _ticketsBought, _rewardsAddress, { from: bob });
      expectEvent(result, "TicketsPurchase", { buyer: bob, lotteryId: "1", numberTickets: "100" });

      console.info(
        `        --> Cost to buy the first 100 tickets: ${result.receipt.gasUsed}`
      );

      expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
        from: bob,
        to: lottery.address,
        value: parseEther("50").toString(),
      });

      result = await lottery.viewLottery("1");
      assert.equal(result[6].toString(), parseEther("50").toString());

      result = await lottery.viewUserInfoForLotteryId(bob, "1", 0, 100);
      const bobTicketIds = [];

      result[0].forEach(function (value) {
        bobTicketIds.push(value.toString());
      });

      const expectedTicketIds = Array.from({ length: 100 }, (_, v) => v.toString());
      assert.includeOrderedMembers(bobTicketIds, expectedTicketIds);

      result = await lottery.viewNumbersAndStatusesForTicketIds(bobTicketIds);
      assert.includeOrderedMembers(result[0].map(String), _ticketsBought);
    });

    it("Carol buys 1 ticket", async () => {
      const _ticketsBought = ["1101010"];
      // Carol buys 1/1/1/1/1/1
      result = await lottery.buyTickets("1", _ticketsBought, _rewardsAddress, { from: carol });
      expectEvent(result, "TicketsPurchase", { buyer: carol, lotteryId: "1", numberTickets: "1" });

      console.info(
        `        --> Cost to buy a stand-alone ticket: ${result.receipt.gasUsed}`
      );

      expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
        from: carol,
        to: lottery.address,
        value: parseEther("0.5").toString(),
      });
    });

    it("David buys 10 tickets", async () => {
      const _ticketsBought = [
        "1111112",
        "1222222",
        "1333333",
        "1444444",
        "1555555",
        "1666666",
        "1777777",
        "1888888",
        "1014001",
        "1999999",
      ];

      result = await lottery.buyTickets("1", _ticketsBought, _rewardsAddress, { from: david });
      expectEvent(result, "TicketsPurchase", { buyer: david, lotteryId: "1", numberTickets: "10" });

      console.info(
        `        --> Cost to buy 10 tickets: ${result.receipt.gasUsed}`
      );

      expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
        from: david,
        to: lottery.address,
        value: parseEther("5").toString(),
      });

    });

    it("Owner does 1M CAKE injection", async () => {
      await mockCake.mintTokens(parseEther("1000000"), { from: alice });
      result = await lottery.injectFunds("1", parseEther("1000000"), { from: alice });
      expectEvent(result, "LotteryInjection", { lotteryId: "1", injectedAmount: parseEther("1000000").toString() });

      console.info(
        `        --> Cost to do injection: ${result.receipt.gasUsed}`
      );

      expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
        from: alice,
        to: lottery.address,
        value: parseEther("1000000").toString(),
      });
    });

    it("Erin buys 100 tickets", async () => {
      const _ticketsBought = [
        "1703000",
        "1733562",
        "1733563",
        "1733564",
        "1733565",
        "1733566",
        "1733567",
        "1733568",
        "1733569",
        "1733570",
        "1733571",
        "1733572",
        "1733573",
        "1733574",
        "1733575",
        "1733576",
        "1733577",
        "1733578",
        "1733579",
        "1733580",
        "1733581",
        "1733582",
        "1733583",
        "1733584",
        "1733585",
        "1733586",
        "1733587",
        "1733588",
        "1733589",
        "1733590",
        "1733591",
        "1733592",
        "1733593",
        "1733594",
        "1733595",
        "1733596",
        "1733597",
        "1733598",
        "1733599",
        "1733600",
        "1733601",
        "1733602",
        "1733603",
        "1733604",
        "1733605",
        "1733606",
        "1733607",
        "1733608",
        "1733609",
        "1733610",
        "1733611",
        "1733612",
        "1733613",
        "1733614",
        "1733615",
        "1733616",
        "1733617",
        "1733618",
        "1733619",
        "1733620",
        "1733621",
        "1733622",
        "1733623",
        "1733624",
        "1733625",
        "1733626",
        "1733627",
        "1733628",
        "1733629",
        "1733630",
        "1733631",
        "1733632",
        "1733633",
        "1733634",
        "1733635",
        "1733636",
        "1733637",
        "1733638",
        "1733639",
        "1733640",
        "1733641",
        "1733642",
        "1733643",
        "1733644",
        "1733645",
        "1733646",
        "1733647",
        "1733648",
        "1733649",
        "1733650",
        "1733651",
        "1733652",
        "1733653",
        "1733654",
        "1733655",
        "1733656",
        "1733657",
        "1733658",
        "1733659",
        "1733660",
      ];

      result = await lottery.buyTickets("1", _ticketsBought, _rewardsAddress, { from: erin });
      expectEvent(result, "TicketsPurchase", { buyer: erin, lotteryId: "1", numberTickets: "100" });
      
      console.info(
        `        --> Cost to buy the first 100 tickets: ${result.receipt.gasUsed}`
      );

      expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
        from: erin,
        to: lottery.address,
        value: parseEther("50").toString(),
      });
    });

    it("Carol buys 2 tickets revert already sold", async () => {
      const _ticketsBought = ["1703000","1111112"];
      // Carol buys 1/1/1/1/1/2
      await expectRevert(lottery.buyTickets("1", _ticketsBought, _rewardsAddress, { from: carol }), "Ticket already sold, choose another number and try it again.");
    });

    it("Operator closes lottery", async () => {
      await randomNumberGenerator.setNextRandomResult("199999999", { from: alice });
      await randomNumberGenerator.changeLatestLotteryId({ from: alice });

      // Time travel
      await time.increaseTo(endTime);
      result = await lottery.closeLottery("1", { from: operator });
      expectEvent(result, "LotteryClose", { lotteryId: "1", firstTicketIdNextLottery: "211" });

      console.info(
        `        --> Cost to close lottery: ${result.receipt.gasUsed}`
      );
    });

    it("Claim rewards when lottery is not claimable", async () => {
      await expectRevert(lottery.distributeReferralRewards("1", { from: injector }), "Lottery not claimable");
    });

    it("Numbers are drawn (9/9/9/9/9/9)", async () => {
      // 3 winning tickets
      resutl = await lottery.drawAndMakeLotteryClaimable("1", { from: operator });
      let status = await lottery.viewLottery("1");
      // 3 claimable
      assert.equal(status[0].toString(), "3");
      assert.equal(status[7].toString(), "1999999");
      console.info(
        `        --> Cost to draw numbers (w/o ChainLink): ${result.receipt.gasUsed}`
      );
    });
    
    it("user has referral rewards amount to claim (true)", async () => {
      console.log(await lottery.hasReferralRewardsToClaim("1", injector, { from: alice }));
    });

    it("Claim referral rewards", async () => {
      // reward amount = tickets * price * reward = 211 * 0.5 * 0.05 = 5.275
      let resutl = await lottery.distributeReferralRewards("1", { from: injector });
      expectEvent(resutl, "DistributeRewards", { claimer: injector, amount: parseEther("5.275").toString() });

      console.info(
        `        --> Cost to claim referral rewards: ${result.receipt.gasUsed}`
      );

      await expectRevert(lottery.distributeReferralRewards("1", { from: carol }), "No rewards for this lottery");
    });

    it("user has referral rewards amount to claim (false)", async () => {
      console.log(await lottery.hasReferralRewardsToClaim("1", injector, { from: alice }));
    });

    it("Carol claims 1st place", async () => {
      // 100,000 CAKE 1st place
      result = await lottery.claimTickets(
        "1",
        ["1101010"],
        { from: carol }
      );

      expectEvent(result, "TicketsClaim", {
        claimer: carol,
        amount: parseEther("100000").toString(),
        lotteryId: "1",
        numberTickets: "1",
      });

      console.info(
        `        --> Cost to claim 1 ticket: ${result.receipt.gasUsed}`
      );

      expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
        from: lottery.address,
        to: carol,
        value: parseEther("100000").toString(),
      });
    });

    it("Erin claims 2st place", async () => {
      // 80,000 CAKE 1st place
      const _ticketsBought = [
        "1703000",
        "1733562",
        "1733563",
        "1733564",
        "1733565",
        "1733566",
        "1733567",
        "1733568",
        "1733569",
        "1733570",
        "1733571",
        "1733572",
        "1733573",
        "1733574",
        "1733575",
        "1733576",
        "1733577",
        "1733578",
        "1733579",
        "1733580",
        "1733581",
        "1733582",
        "1733583",
        "1733584",
        "1733585",
        "1733586",
        "1733587",
        "1733588",
        "1733589",
        "1733590",
        "1733591",
        "1733592",
        "1733593",
        "1733594",
        "1733595",
        "1733596",
        "1733597",
        "1733598",
        "1733599",
        "1733600",
        "1733601",
        "1733602",
        "1733603",
        "1733604",
        "1733605",
        "1733606",
        "1733607",
        "1733608",
        "1733609",
        "1733610",
        "1733611",
        "1733612",
        "1733613",
        "1733614",
        "1733615",
        "1733616",
        "1733617",
        "1733618",
        "1733619",
        "1733620",
        "1733621",
        "1733622",
        "1733623",
        "1733624",
        "1733625",
        "1733626",
        "1733627",
        "1733628",
        "1733629",
        "1733630",
        "1733631",
        "1733632",
        "1733633",
        "1733634",
        "1733635",
        "1733636",
        "1733637",
        "1733638",
        "1733639",
        "1733640",
        "1733641",
        "1733642",
        "1733643",
        "1733644",
        "1733645",
        "1733646",
        "1733647",
        "1733648",
        "1733649",
        "1733650",
        "1733651",
        "1733652",
        "1733653",
        "1733654",
        "1733655",
        "1733656",
        "1733657",
        "1733658",
        "1733659",
        "1733660",
      ];
      result = await lottery.claimTickets(
        "1",
        _ticketsBought,
        { from: erin }
      );

      expectEvent(result, "TicketsClaim", {
        claimer: erin,
        amount: parseEther("80000").toString(),
        lotteryId: "1",
        numberTickets: "100",
      });

      console.info(
        `        --> Cost to claim 100 ticket: ${result.receipt.gasUsed}`
      );

      expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
        from: lottery.address,
        to: erin,
        value: parseEther("80000").toString(),
      });
    });

    it("Bob claims 3st place", async () => {
      // 50,000 CAKE 1st place
      const _ticketsBought = [
        "1000000",
        "1234562",
        "1234563",
        "1234564",
        "1234565",
        "1234566",
        "1234567",
        "1234568",
        "1234569",
        "1234570",
        "1334571",
        "1334572",
        "1334573",
        "1334574",
        "1334575",
        "1334576",
        "1334577",
        "1334578",
        "1334579",
        "1334580",
        "1434581",
        "1434582",
        "1434583",
        "1434584",
        "1434585",
        "1434586",
        "1434587",
        "1434588",
        "1434589",
        "1534590",
        "1534591",
        "1534592",
        "1534593",
        "1534594",
        "1534595",
        "1534596",
        "1534597",
        "1534598",
        "1534599",
        "1634600",
        "1634601",
        "1634602",
        "1634603",
        "1634604",
        "1634605",
        "1634606",
        "1634607",
        "1634608",
        "1634609",
        "1634610",
        "1634611",
        "1634612",
        "1634613",
        "1634614",
        "1634615",
        "1634616",
        "1634617",
        "1634618",
        "1634619",
        "1634620",
        "1634621",
        "1634622",
        "1634623",
        "1634624",
        "1634625",
        "1634626",
        "1634627",
        "1634628",
        "1634629",
        "1634630",
        "1634631",
        "1634632",
        "1634633",
        "1634634",
        "1634635",
        "1634636",
        "1634637",
        "1634638",
        "1634639",
        "1634640",
        "1634641",
        "1634642",
        "1634643",
        "1634644",
        "1634645",
        "1634646",
        "1634647",
        "1634648",
        "1634649",
        "1634650",
        "1634651",
        "1634652",
        "1634653",
        "1634654",
        "1634655",
        "1634656",
        "1634657",
        "1634658",
        "1634659",
        "1634660",
      ];
      result = await lottery.claimTickets(
        "1",
        _ticketsBought,
        { from: bob }
      );

      expectEvent(result, "TicketsClaim", {
        claimer: bob,
        amount: parseEther("50000").toString(),
        lotteryId: "1",
        numberTickets: "100",
      });

      console.info(
        `        --> Cost to claim 100 ticket: ${result.receipt.gasUsed}`
      );

      expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
        from: lottery.address,
        to: bob,
        value: parseEther("50000").toString(),
      });
    });

    it("David claim no winner ticket", async () => {
      // sin suerte david 
      const _ticketsBought = [
        "1111112",
        "1222222",
        "1333333",
        "1444444",
        "1555555",
        "1666666",
        "1777777",
        "1888888",
        "1014001",
        "1999999",
      ];

      await expectRevert(lottery.claimTickets("1", _ticketsBought, { from: david }), "No prize for this lottery");
    });

    it("Carol claims 1st place again", async () => {
      // 100,000 CAKE 1st place
      await expectRevert(lottery.claimTickets("1", ["1111111"], { from: carol }), "No prize for this lottery");
    });

    describe("LOTTERY #2 - CUSTOM RANDOMNESS - Exceptions", async () => {
      it("Operator cannot close lottery not open", async () => {
        await expectRevert(lottery.closeLottery("1", { from: operator }), "Lottery not open");
      });

      it("Operator cannot inject funds in a lottery that is not Open status", async () => {
        await expectRevert(lottery.injectFunds("1", parseEther("10"), { from: alice }), "Lottery not open");
        await expectRevert(lottery.injectFunds("2", parseEther("10"), { from: alice }), "Lottery not open");
      });

      it("Operator cannot draw numbers for previous lottery", async () => {
        await expectRevert(
          lottery.drawAndMakeLotteryClaimable("1", { from: operator }),
          "Lottery not close"
        );
      });

      it("User cannot buy 1 ticket for old lottery", async () => {
        await expectRevert(lottery.buyTickets("1", ["1999999"], _rewardsAddress, { from: bob }), "Lottery is not open");
      });

      it("User cannot buy 1 ticket for future lottery", async () => {
        await expectRevert(lottery.buyTickets("2", ["1999999"], _rewardsAddress, { from: bob }), "Lottery is not open");
      });

      it("Operator cannot start lottery if length is too short/long", async () => {
        const currentLengthLottery = _lengthLottery;

        _lengthLottery = await lottery.MIN_LENGTH_LOTTERY();

        let endTimeTarget = new BN(await time.latest()).add(_lengthLottery).sub(new BN("10"));

        await expectRevert(
          lottery.startLottery(
            endTimeTarget,
            _priceTicketInBusd,
            _minTicketsToSell,
            _maxTicketsToSell,
            _prizes,
            _referralReward,
            {from: operator,}
          ),
          "Lottery length outside of range"
        );

        _lengthLottery = await lottery.MAX_LENGTH_LOTTERY();

        endTimeTarget = new BN(await time.latest()).add(_lengthLottery).add(new BN("100"));

        await expectRevert(
          lottery.startLottery(
            endTimeTarget,
            _priceTicketInBusd,
            _minTicketsToSell,
            _maxTicketsToSell,
            _prizes,
            _referralReward, {
            from: operator,
          }),
          "Lottery length outside of range"
        );

        // Set it back to previous value
        _lengthLottery = currentLengthLottery;

        endTime = new BN(await time.latest()).add(_lengthLottery);
      });

      it("Operator cannot start lottery if ticket price too low or too high", async () => {
        let newPriceTicketInCake = parseEther("0.0049999999");

        await expectRevert(
          lottery.startLottery(
            endTime,
            newPriceTicketInCake,
            _minTicketsToSell,
            _maxTicketsToSell,
            _prizes,
            _referralReward, {
            from: operator,
          }),
          "Outside of limits"
        );

        newPriceTicketInCake = parseEther("0.0049999999");

        await expectRevert(
          lottery.startLottery(
            endTime,
            newPriceTicketInCake,
            _minTicketsToSell,
            _maxTicketsToSell,
            _prizes,
            _referralReward, {
            from: operator,
          }),
          "Outside of limits"
        );
      });

      it("Operator cannot close lottery that is not started", async () => {
        await expectRevert(lottery.closeLottery("2", { from: operator }), "Lottery not open");
      });

      it("Operator starts lottery", async () => {
        endTime = new BN(await time.latest()).add(_lengthLottery);

        result = await lottery.startLottery(
          endTime,
          _priceTicketInBusd,
          "2",
          _maxTicketsToSell,
          [parseEther("1"),parseEther("0.5")],
          _referralReward,
          { from: operator }
        );

        expectEvent(result, "LotteryOpen", {
          lotteryId: "2",
          startTime: (await time.latest()).toString(),
          endTime: endTime.toString(),
          priceTicketInBusd: _priceTicketInBusd.toString(),
          firstTicketId: "211",
          injectedAmount: "0",
        });
      });

      it("Operator cannot close lottery", async () => {
        await expectRevert(lottery.closeLottery("2", { from: operator }), "Lottery not over");
      });

      it("Operator cannot draw numbers", async () => {
        await expectRevert(
          lottery.drawAndMakeLotteryClaimable("2", { from: operator }),
          "Lottery not close"
        );
      });

      it("Operator cannot start a second lottery", async () => {
        await expectRevert(
          lottery.startLottery(
            _lengthLottery,
            _priceTicketInBusd,
            _minTicketsToSell,
            _maxTicketsToSell,
            _prizes,
            _referralReward,
            {from: operator,}
          ),
          "Not time to start lottery"
        );
      });

      it("User cannot buy 0 ticket", async () => {
        await expectRevert(lottery.buyTickets("2", [], _rewardsAddress, { from: bob }), "No ticket specified");
      });

      it("User cannot buy more than the limit of tickets per transaction", async () => {
        const _maxNumberTickets = "5"; // 6 --> rejected // 5 --> accepted
        await lottery.setMaxNumberTicketsPerBuy(_maxNumberTickets, { from: alice });

        await expectRevert(
          lottery.buyTickets("2", ["1999999", "1999998", "1999999", "1999999", "1999998", "1999999"], _rewardsAddress, { from: bob }),
          "Too many tickets"
        );

        // Sets limit at 100 tickets
        await lottery.setMaxNumberTicketsPerBuy("100", { from: alice });
      });

      it("User cannot buy tickets if one of the numbers is outside of range", async () => {
        await expectRevert(
          lottery.buyTickets("2", ["1999999", "2199998", "1999991", "1999992", "1999998", "1999993"], _rewardsAddress, { from: bob }),
          "Outside range"
        );

        await expectRevert(
          lottery.buyTickets("2", ["1999999", "1929998", "1999991", "1999992", "1999997", "59999"], _rewardsAddress, { from: bob }),
          "Outside range"
        );
      });

      it("Bob buys 2 tickets", async () => {
        await lottery.buyTickets("2", ["1999919", "1569455"], _rewardsAddress, { from: bob });
      });

      it("David buys 10 tickets", async () => {
        const _ticketsBought = [
          "1111112",
          "1222222",
          "1333333",
          "1444444",
          "1555555",
          "1666666",
          "1777777",
          "1888888",
          "1014001",
          "1999999",
        ];
  
        result = await lottery.buyTickets("2", _ticketsBought, _rewardsAddress, { from: david });
        expectEvent(result, "TicketsPurchase", { buyer: david, lotteryId: "2", numberTickets: "10" });
  
        console.info(
          `        --> Cost to buy 10 tickets: ${result.receipt.gasUsed}`
        );
  
        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: david,
          to: lottery.address,
          value: parseEther("5").toString(),
        });
  
      });

      it("User cannot claim tickets if not over", async () => {
        await expectRevert(
          lottery.claimTickets("2", ["1999995", "1569995"], { from: bob }),
          "Lottery not claimable"
        );
      });

      it("Cannot buy ticket when it is end time", async () => {
        // Time travel
        await time.increaseTo(endTime);
        await expectRevert(lottery.buyTickets("2", ["1369956", "1369955"], _rewardsAddress, { from: bob }), "Lottery is over");
      });

      it("Cannot change generator number", async () => {
        await expectRevert(
          lottery.changeRandomGenerator(randomNumberGenerator.address, { from: alice }),
          "Lottery not in claimable"
        );
      });

      it("Operator cannot draw numbers if the lotteryId isn't updated in RandomGenerator", async () => {
        await randomNumberGenerator.setNextRandomResult("199999994", { from: alice });

        result = await lottery.closeLottery("2", { from: operator });
        expectEvent(result, "LotteryClose", { lotteryId: "2", firstTicketIdNextLottery: "223" });

        await expectRevert(
          lottery.drawAndMakeLotteryClaimable("2", { from: operator }),
          "Numbers not drawn"
        );

        await randomNumberGenerator.changeLatestLotteryId({ from: alice });

        // 0 winning ticket, funds are not rolled over
        result = await lottery.drawAndMakeLotteryClaimable("2", { from: operator });

        expectEvent(result, "LotteryNumberDrawn", {
          lotteryId: "2",
          finalNumber: "1999994",
          countWinningTickets: "2",
        });

        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: lottery.address,
          to: treasury,
          value: parseEther("3620.0804").toString(),
        });
      });
      /*
      it("test tickets", async () => {
        let tickets = await lottery._winners(3)
        console.log(tickets[0].toString());
        console.log(tickets[1].toString());
        console.log(tickets[2].toString());
        console.log(tickets[3].toString());
        console.log(tickets[4].toString());
        console.log("--------------------------------------------------------------------------------------------------");
        let ticket2 = await lottery._winners(4)
        console.log(ticket2[0].toString());
        console.log(ticket2[1].toString());
        console.log(ticket2[2].toString());
        console.log(ticket2[3].toString());
        console.log(tickets[4].toString());
        console.log("--------------------------------------------------------------------------------------------------");
        let ticket3 = await lottery._winners(5)
        console.log(ticket3[0].toString());
        console.log(ticket3[1].toString());
        console.log(ticket3[2].toString());
        console.log(ticket3[3].toString());
        console.log(tickets[4].toString());
  
        let rand = await lottery.getRamd("2");
        console.log(rand[0].toString());
        console.log(rand[1].toString());
        console.log("--------------------------------------------------------------------------------------------------");
  
        let arr = await lottery.shuffle("2", rand[0].toString())
        // console.log(arr.length);
        for (var i = 0; i < arr.length; i++) {
          console.log(arr[i].toString());
        }
        console.log("--------------------------------------------------------------------------------------------------");
        arr2 = await lottery.shuffle("2", rand[1].toString())
        for (var j = 0; j < arr2.length; j++) {
          console.log(arr2[j].toString());
        }
      });
      */
      
      it("David claim 2 winner tickets", async () => {
        // sin suerte david 
        const _ticketsBought = [
          "1111112",
          "1222222",
          "1333333",
          "1444444",
          "1555555",
          "1666666",
          "1777777",
          "1888888",
          "1014001",
          "1999999",
        ];

        result = await lottery.claimTickets(
          "2",
          _ticketsBought,
          { from: david }
        );
  
        expectEvent(result, "TicketsClaim", {
          claimer: david,
          amount: parseEther("1.5").toString(),
          lotteryId: "2",
          numberTickets: "10",
        });
  
        console.info(
          `        --> Cost to claim 10 ticket: ${result.receipt.gasUsed}`
        );
  
        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: lottery.address,
          to: erin,
          value: parseEther("1.5").toString(),
        });
      });

      it("Bob, Erin and Carol claim no winner ticket", async () => {
        await expectRevert(lottery.claimTickets("2", ["1999919","1569455"], { from: bob }), "No prize for this lottery");
        await expectRevert(lottery.claimTickets("2", ["1014001"], { from: erin }), "No prize for this lottery");
        await expectRevert(lottery.claimTickets("2", 
          ["1111112","1222222","1333333","1444444","1555555","1666666","1777777","1888888","1014001","1999999",],
          { from: carol }), "No prize for this lottery"
        );
      });

      it("Lottery starts, close, and numbers get drawn if min tickets to sell target not reached", async () => {
        endTime = new BN(await time.latest()).add(_lengthLottery);

        result = await lottery.startLottery(
          endTime,
          _priceTicketInBusd,
          "2",
          _maxTicketsToSell,
          _prizes,
          _referralReward,
          { from: operator }
        );

        expectEvent(result, "LotteryOpen", {
          lotteryId: "3",
          startTime: (await time.latest()).toString(),
          endTime: endTime.toString(),
          priceTicketInBusd: _priceTicketInBusd.toString(),
          firstTicketId: "223",
          injectedAmount: "0",
        });

        await time.increaseTo(endTime);
        result = await lottery.closeLottery("3", { from: operator });

        expectEvent(result, "LotteryClose", { lotteryId: "3", firstTicketIdNextLottery: "223" });

        await randomNumberGenerator.changeLatestLotteryId({ from: alice });

        // 0 winner and lottery status = unrealized
        await expectRevert(lottery.drawAndMakeLotteryClaimable("3", { from: operator }), "Lottery not close");

      });

      it("Operator starts lottery", async () => {
        endTime = new BN(await time.latest()).add(_lengthLottery);

        result = await lottery.startLottery(
          endTime,
          _priceTicketInBusd,
          _minTicketsToSell,
          _maxTicketsToSell,
          [parseEther("2"), parseEther("1"), parseEther("0.5")],
          _referralReward,
          { from: operator }
        );

        expectEvent(result, "LotteryOpen", {
          lotteryId: "4",
          startTime: (await time.latest()).toString(),
          endTime: endTime.toString(),
          priceTicketInBusd: _priceTicketInBusd.toString(),
          firstTicketId: "223",
          injectedAmount: "0",
        });
      });

      it("Bob buys 100 tickets", async () => {
        const _ticketsBought = [
          "1000000",
          "1234562",
          "1234563",
          "1234564",
          "1234565",
          "1234566",
          "1234567",
          "1234568",
          "1234569",
          "1234570",
          "1334571",
          "1334572",
          "1334573",
          "1334574",
          "1334575",
          "1334576",
          "1334577",
          "1334578",
          "1334579",
          "1334580",
          "1434581",
          "1434582",
          "1434583",
          "1434584",
          "1434585",
          "1434586",
          "1434587",
          "1434588",
          "1434589",
          "1534590",
          "1534591",
          "1534592",
          "1534593",
          "1534594",
          "1534595",
          "1534596",
          "1534597",
          "1534598",
          "1534599",
          "1634600",
          "1634601",
          "1634602",
          "1634603",
          "1634604",
          "1634605",
          "1634606",
          "1634607",
          "1634608",
          "1634609",
          "1634610",
          "1634611",
          "1634612",
          "1634613",
          "1634614",
          "1634615",
          "1634616",
          "1634617",
          "1634618",
          "1634619",
          "1634620",
          "1634621",
          "1634622",
          "1634623",
          "1634624",
          "1634625",
          "1634626",
          "1634627",
          "1634628",
          "1634629",
          "1634630",
          "1634631",
          "1634632",
          "1634633",
          "1634634",
          "1634635",
          "1634636",
          "1634637",
          "1634638",
          "1634639",
          "1634640",
          "1634641",
          "1634642",
          "1634643",
          "1634644",
          "1634645",
          "1634646",
          "1634647",
          "1634648",
          "1634649",
          "1634650",
          "1634651",
          "1634652",
          "1634653",
          "1634654",
          "1634655",
          "1634656",
          "1634657",
          "1634658",
          "1634659",
          "1634660",
        ];
  
        result = await lottery.buyTickets("4", _ticketsBought, _rewardsAddress, { from: bob });
  
        expectEvent(result, "TicketsPurchase", { buyer: bob, lotteryId: "4", numberTickets: "100" });
  
        console.info(
          `        --> Cost to buy the first 100 tickets: ${result.receipt.gasUsed}`
        );
  
        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: bob,
          to: lottery.address,
          value: parseEther("50").toString(),
        });
      });

      it("Carol buys 1 ticket", async () => {
        const _ticketsBought = ["1111111"];
        // Carol buys 1/1/1/1/1/1
        result = await lottery.buyTickets("4", _ticketsBought, _rewardsAddress, { from: carol });
        expectEvent(result, "TicketsPurchase", { buyer: carol, lotteryId: "4", numberTickets: "1" });
  
        console.info(
          `        --> Cost to buy a stand-alone ticket: ${result.receipt.gasUsed}`
        );
  
        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: carol,
          to: lottery.address,
          value: parseEther("0.5").toString(),
        });
      });
  
      it("David buys 10 tickets", async () => {
        const _ticketsBought = [
          "1111112",
          "1222222",
          "1333333",
          "1444444",
          "1555555",
          "1666666",
          "1777777",
          "1888888",
          "1014001",
          "1999999",
        ];
  
        result = await lottery.buyTickets("4", _ticketsBought, _rewardsAddress, { from: david });
        expectEvent(result, "TicketsPurchase", { buyer: david, lotteryId: "4", numberTickets: "10" });
  
        console.info(
          `        --> Cost to buy 10 tickets: ${result.receipt.gasUsed}`
        );
  
        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: david,
          to: lottery.address,
          value: parseEther("5").toString(),
        });
  
      });
  
      it("Erin buys 100 tickets", async () => {
        const _ticketsBought = [
          "1703000",
          "1733562",
          "1733563",
          "1733564",
          "1733565",
          "1733566",
          "1733567",
          "1733568",
          "1733569",
          "1733570",
          "1733571",
          "1733572",
          "1733573",
          "1733574",
          "1733575",
          "1733576",
          "1733577",
          "1733578",
          "1733579",
          "1733580",
          "1733581",
          "1733582",
          "1733583",
          "1733584",
          "1733585",
          "1733586",
          "1733587",
          "1733588",
          "1733589",
          "1733590",
          "1733591",
          "1733592",
          "1733593",
          "1733594",
          "1733595",
          "1733596",
          "1733597",
          "1733598",
          "1733599",
          "1733600",
          "1733601",
          "1733602",
          "1733603",
          "1733604",
          "1733605",
          "1733606",
          "1733607",
          "1733608",
          "1733609",
          "1733610",
          "1733611",
          "1733612",
          "1733613",
          "1733614",
          "1733615",
          "1733616",
          "1733617",
          "1733618",
          "1733619",
          "1733620",
          "1733621",
          "1733622",
          "1733623",
          "1733624",
          "1733625",
          "1733626",
          "1733627",
          "1733628",
          "1733629",
          "1733630",
          "1733631",
          "1733632",
          "1733633",
          "1733634",
          "1733635",
          "1733636",
          "1733637",
          "1733638",
          "1733639",
          "1733640",
          "1733641",
          "1733642",
          "1733643",
          "1733644",
          "1733645",
          "1733646",
          "1733647",
          "1733648",
          "1733649",
          "1733650",
          "1733651",
          "1733652",
          "1733653",
          "1733654",
          "1733655",
          "1733656",
          "1733657",
          "1733658",
          "1733659",
          "1733660",
        ];
  
        result = await lottery.buyTickets("4", _ticketsBought, _rewardsAddress, { from: erin });
        expectEvent(result, "TicketsPurchase", { buyer: erin, lotteryId: "4", numberTickets: "100" });
        
        console.info(
          `        --> Cost to buy the first 100 tickets: ${result.receipt.gasUsed}`
        );
  
        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: bob,
          to: lottery.address,
          value: parseEther("50").toString(),
        });
      });

      it("Operator closes lottery", async () => {
        await randomNumberGenerator.setNextRandomResult("199999996", { from: alice });
        await randomNumberGenerator.changeLatestLotteryId({ from: alice });
  
        // Time travel
        await time.increaseTo(endTime);
        result = await lottery.closeLottery("4", { from: operator });
        expectEvent(result, "LotteryClose", { lotteryId: "4", firstTicketIdNextLottery: "434" });
  
        console.info(
          `        --> Cost to close lottery: ${result.receipt.gasUsed}`
        );
      });
  
      it("Numbers are drawn (9/9/9/9/9/9)", async () => {
        // 3 winning tickets
        resutl = await lottery.drawAndMakeLotteryClaimable("4", { from: operator });
        let status = await lottery.viewLottery("4");
        // 3 claimable
        assert.equal(status[0].toString(), "3");
        assert.equal(status[7].toString(), "1999996");
  
        console.info(
          `        --> Cost to draw numbers (w/o ChainLink): ${result.receipt.gasUsed}`
        );
      });

      it("Change the random generator (to existing one)", async () => {
        result = await lottery.changeRandomGenerator(randomNumberGenerator.address, { from: alice });
        expectEvent(result, "NewRandomGenerator", { randomGenerator: randomNumberGenerator.address });
      });

      it("Operator starts lottery", async () => {
        endTime = new BN(await time.latest()).add(_lengthLottery);

        result = await lottery.startLottery(
          endTime,
          _priceTicketInBusd,
          _minTicketsToSell,
          _maxTicketsToSell,
          _prizes,
          _referralReward,
          { from: operator }
        );

        expectEvent(result, "LotteryOpen", {
          lotteryId: "5",
          startTime: (await time.latest()).toString(),
          endTime: endTime.toString(),
          priceTicketInBusd: _priceTicketInBusd.toString(),
          firstTicketId: "434",
          injectedAmount: "0",
        });
      });

      it("Carol buys 1 ticket", async () => {
        const _ticketsBought = ["1111111"];
        // Carol buys 1/1/1/1/1/1
        result = await lottery.buyTickets("5", _ticketsBought, _rewardsAddress, { from: carol });
        expectEvent(result, "TicketsPurchase", { buyer: carol, lotteryId: "5", numberTickets: "1" });
  
        console.info(
          `        --> Cost to buy a stand-alone ticket: ${result.receipt.gasUsed}`
        );
  
        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: carol,
          to: lottery.address,
          value: parseEther("0.5").toString(),
        });
      });
  
      it("David buys 10 tickets", async () => {
        const _ticketsBought = [
          "1111112",
          "1222222",
          "1333333",
          "1444444",
          "1555555",
          "1666666",
          "1777777",
          "1888888",
          "1014001",
          "1999999",
        ];
  
        result = await lottery.buyTickets("5", _ticketsBought, _rewardsAddress, { from: david });
        expectEvent(result, "TicketsPurchase", { buyer: david, lotteryId: "5", numberTickets: "10" });
  
        console.info(
          `        --> Cost to buy 10 tickets: ${result.receipt.gasUsed}`
        );
  
        expectEvent.inTransaction(result.receipt.transactionHash, mockCake, "Transfer", {
          from: david,
          to: lottery.address,
          value: parseEther("5").toString(),
        });
  
      });

      it("Operator closes lottery", async () => {
        await randomNumberGenerator.setNextRandomResult("199999997", { from: alice });
        await randomNumberGenerator.changeLatestLotteryId({ from: alice });
  
        // Time travel
        await time.increaseTo(endTime);
        result = await lottery.closeLottery("5", { from: operator });
        expectEvent(result, "LotteryClose", { lotteryId: "5", firstTicketIdNextLottery: "445" });
  
        console.info(
          `        --> Cost to close lottery: ${result.receipt.gasUsed}`
        );
      });

      it("get funds to withdraw in a unrealized lottery (true)", async () => {
        console.log(await lottery.hasAmountToWithdraw("5", carol, { from: david }));
      });

      it("Withdraw funds in a unrealized lottery", async () => {
        result = await lottery.withdrawFunds("5", { from: carol });
        expectEvent(result, "ReturnFunds", { owner: carol, amount: parseEther("0.5").toString() });

        result2 = await lottery.withdrawFunds("5", { from: david });
        expectEvent(result2, "ReturnFunds", { owner: david, amount: parseEther("5").toString() });

        await expectRevert(lottery.withdrawFunds("5", { from: bob }), "No amount to return for this lottery");
      });

      it("get funds to withdraw after witdraw in a unrealized lottery (false)", async () => {
        console.log(await lottery.hasAmountToWithdraw("5", carol, { from: david }));
      });

      it("Claim rewards when lottery unrealized", async () => {
        await expectRevert(lottery.distributeReferralRewards("5", { from: injector }), "Lottery not claimable");
      });

      it("Operator starts lottery", async () => {
        endTime = new BN(await time.latest()).add(_lengthLottery);
        let _priceTicketInBusd = parseEther("5");
        let _minTicketsToSell = "120";
        let _maxTicketsToSell = "121";
        let _prizes = [
          parseEther("50"),
          parseEther("50"),
          parseEther("50"),
          parseEther("50"),
          parseEther("50"),
          parseEther("50"),
          parseEther("50"),
          parseEther("50"),
          parseEther("50"),
          parseEther("50")
        ];
        let _referralReward = "1000";
  
        result = await lottery.startLottery(
          endTime,
          _priceTicketInBusd,
          _minTicketsToSell,
          _maxTicketsToSell,
          _prizes,
          _referralReward,
          { from: operator }
        );
  
        expectEvent(result, "LotteryOpen", {
          lotteryId: "6",
          startTime: (await time.latest()).toString(),
          endTime: endTime.toString(),
          priceTicketInBusd: _priceTicketInBusd.toString(),
          firstTicketId: "445",
          injectedAmount: "0",
        });
  
        console.info(
          `        --> Cost to start the lottery: ${result.receipt.gasUsed}`
        );
      });

      it("buy all 120 tickets", async () => {
        let _ticketsBought2 = [
          "1000000",
          "1234562",
          "1234563",
          "1234564",
          "1234565",
          "1234566",
          "1234567",
          "1234568",
          "1234569",
          "1234570",
          "1334571",
          "1334572",
          "1334573",
          "1334574",
          "1334575",
          "1334576",
          "1334577",
          "1334578",
          "1334579",
          "1334580",
          "1434581",
          "1434582",
          "1434583",
          "1434584",
          "1434585"
        ];
  
        result = await lottery.buyTickets("6", _ticketsBought2, _rewardsAddress, { from: carol });
        expectEvent(result, "TicketsPurchase", { buyer: carol, lotteryId: "6", numberTickets: "25" });

        _ticketsBought2 = [
          "1434586",
          "1434587",
          "1434588",
          "1434589",
          "1534590",
          "1534591",
          "1534592",
          "1534593",
          "1534594",
          "1534595",
          "1534596",
          "1534597",
          "1534598",
          "1534599",
          "1634600",
          "1634601",
          "1634602",
          "1634603",
          "1634604",
          "1634605",
          "1634606",
          "1634607",
          "1634608",
          "1634609",
          "1634610"
        ];
  
        result = await lottery.buyTickets("6", _ticketsBought2, _rewardsAddress, { from: bob });
        expectEvent(result, "TicketsPurchase", { buyer: bob, lotteryId: "6", numberTickets: "25" });

        _ticketsBought2 = [
          "1634611",
          "1634612",
          "1634613",
          "1634614",
          "1634615",
          "1634616",
          "1634617",
          "1634618",
          "1634619",
          "1634620",
          "1634621",
          "1634622",
          "1634623",
          "1634624",
          "1634625",
          "1634626",
          "1634627",
          "1634628",
          "1634629",
          "1634630",
          "1634631",
          "1634632",
          "1634633",
          "1634634",
          "1634635"
        ];
  
        result = await lottery.buyTickets("6", _ticketsBought2, _rewardsAddress, { from: david });
        expectEvent(result, "TicketsPurchase", { buyer: david, lotteryId: "6", numberTickets: "25" });

        _ticketsBought2 = [
          "1634636",
          "1634637",
          "1634638",
          "1634639",
          "1634640",
          "1634641",
          "1634642",
          "1634643",
          "1634644",
          "1634645",
          "1634646",
          "1634647",
          "1634648",
          "1634649",
          "1634650",
          "1634651",
          "1634652",
          "1634653",
          "1634654",
          "1634655",
          "1634656",
          "1634657",
          "1634658",
          "1634659",
          "1634660",
        ];
  
        result = await lottery.buyTickets("6", _ticketsBought2, _rewardsAddress, { from: erin });
        expectEvent(result, "TicketsPurchase", { buyer: erin, lotteryId: "6", numberTickets: "25" });

        _ticketsBought2 = [
          "1703000",
          "1733562",
          "1733563",
          "1733564",
          "1733565",
          "1733566",
          "1733567",
          "1733568",
          "1733569",
          "1733570",
          "1733571",
          "1733572",
          "1733573",
          "1733574",
          "1733575",
          "1733576",
          "1733577",
          "1733578",
          "1733579",
          "1733580",
        ];
  
        result = await lottery.buyTickets("6", _ticketsBought2, _rewardsAddress, { from: bob });
        expectEvent(result, "TicketsPurchase", { buyer: bob, lotteryId: "6", numberTickets: "20" });
      });

      it("Operator closes lottery", async () => {
        await randomNumberGenerator.setNextRandomResult("199999999", { from: alice });
        await randomNumberGenerator.changeLatestLotteryId({ from: alice });
  
        // Time travel
        await time.increaseTo(endTime);
        result = await lottery.closeLottery("6", { from: operator });
        expectEvent(result, "LotteryClose", { lotteryId: "6", firstTicketIdNextLottery: "565" });
  
        console.info(
          `        --> Cost to close lottery: ${result.receipt.gasUsed}`
        );
      });

      it("Numbers are drawn (9/9/9/9/9/9)", async () => {
        // 3 winning tickets
        resutl = await lottery.drawAndMakeLotteryClaimable("6", { from: operator });
        let status = await lottery.viewLottery("6");
        // 3 claimable
        assert.equal(status[0].toString(), "3");
        assert.equal(status[7].toString(), "1999999");
        console.info(
          `        --> Cost to draw numbers (w/o ChainLink): ${result.receipt.gasUsed}`
        );
      });
    });

    describe("Role exceptions", async () => {
      it("Owner can recover funds only if not CAKE token", async () => {
        // Deploy Random Token
        const randomToken = await MockERC20.new("Random Token", "RT", parseEther("100"), {
          from: alice,
        });

        // Transfer token by "accident"
        await randomToken.transfer(lottery.address, parseEther("1"));

        result = await lottery.recoverWrongTokens(randomToken.address, parseEther("1"), { from: alice });

        expectEvent(result, "AdminTokenRecovery", { token: randomToken.address, amount: parseEther("1").toString() });

        await expectRevert(
          lottery.recoverWrongTokens(mockCake.address, parseEther("1"), { from: alice }),
          "Cannot be BUSD token"
        );
      });

      it("Only operator can call operator functions", async () => {
        await expectRevert(
          lottery.startLottery(
            _lengthLottery,
            _priceTicketInBusd,
            _minTicketsToSell,
            _maxTicketsToSell,
            _prizes,
            _referralReward, {
            from: alice,
          }),
          "Not operator"
        );

        await expectRevert(lottery.closeLottery("2", { from: alice }), "Not operator");
        await expectRevert(lottery.drawAndMakeLotteryClaimable("2", { from: alice }), "Not operator");
      });

      it("Only owner/injector can call owner functions", async () => {
        await expectRevert(
          lottery.setMaxNumberTicketsPerBuy("1", { from: operator }),
          "Ownable: caller is not the owner"
        );

        await expectRevert(lottery.injectFunds("1", parseEther("10"), { from: operator }), "Not owner or injector");

        await expectRevert(
          lottery.setOperatorAndTreasuryAndInjectorAddresses(operator, treasury, injector, { from: operator }),
          "Ownable: caller is not the owner"
        );

        await expectRevert(
          lottery.recoverWrongTokens(mockCake.address, parseEther("10"), { from: operator }),
          "Ownable: caller is not the owner"
        );

        await expectRevert(
          lottery.changeRandomGenerator(randomNumberGenerator.address, { from: operator }),
          "Ownable: caller is not the owner"
        );
      });

      it("Revert statements work in owner functions", async () => {
        await expectRevert(lottery.setMaxNumberTicketsPerBuy("0", { from: alice }), "Must be > 0");
        await expectRevert(
          lottery.setOperatorAndTreasuryAndInjectorAddresses(operator, constants.ZERO_ADDRESS, injector, {
            from: alice,
          }),
          "Cannot be zero address"
        );
        await expectRevert(
          lottery.setOperatorAndTreasuryAndInjectorAddresses(constants.ZERO_ADDRESS, treasury, injector, {
            from: alice,
          }),
          "Cannot be zero address"
        );
        await expectRevert(
          lottery.setOperatorAndTreasuryAndInjectorAddresses(operator, treasury, constants.ZERO_ADDRESS, {
            from: alice,
          }),
          "Cannot be zero address"
        );
      });
    });
});
});

/*
  
    it("test tickets", async () => {
      let tickets = await lottery._winners(0)
      console.log(tickets[0].toString());
      console.log(tickets[1].toString());
      console.log(tickets[2].toString());
      console.log(tickets[3].toString());
      console.log(tickets[4].toString());
      console.log("--------------------------------------------------------------------------------------------------");
      let ticket2 = await lottery._winners(1)
      console.log(ticket2[0].toString());
      console.log(ticket2[1].toString());
      console.log(ticket2[2].toString());
      console.log(ticket2[3].toString());
      console.log(tickets[4].toString());
      console.log("--------------------------------------------------------------------------------------------------");
      let ticket3 = await lottery._winners(2)
      console.log(ticket3[0].toString());
      console.log(ticket3[1].toString());
      console.log(ticket3[2].toString());
      console.log(ticket3[3].toString());
      console.log(tickets[4].toString());

      let rand = await lottery.getRamd("3");
      console.log(rand[0].toString());
      console.log(rand[1].toString());
      console.log(rand[2].toString());
      console.log("--------------------------------------------------------------------------------------------------");

      let arr = await lottery.shuffle("1", rand[0].toString())
      // console.log(arr.length);
      for (var i = 0; i < arr.length; i++) {
        console.log(arr[i].toString());
      }
      console.log("--------------------------------------------------------------------------------------------------");
      arr2 = await lottery.shuffle("1", rand[1].toString())
      for (var j = 0; j < arr2.length; j++) {
        console.log(arr2[j].toString());
      }
    });
  it("test tickets", async () => {      
    let tickets = await lottery._winners(0)
    console.log(tickets[0].toString());
    console.log(tickets[1].toString());
    console.log(tickets[2].toString());
    console.log(tickets[3].toString());
    console.log(tickets[4].toString());
    console.log("--------------------------------------------------------------------------------------------------");
    let ticket2 = await lottery._winners(1)
    console.log(ticket2[0].toString());
    console.log(ticket2[1].toString());
    console.log(ticket2[2].toString());
    console.log(ticket2[3].toString());
    console.log(tickets[4].toString());
    console.log("--------------------------------------------------------------------------------------------------");
    let ticket3 = await lottery._winners(2)
    console.log(ticket3[0].toString());
    console.log(ticket3[1].toString());
    console.log(ticket3[2].toString());
    console.log(ticket3[3].toString());
    console.log(tickets[4].toString());
    
    let sm = await lottery.tickIds("1")
    for (var k = 0; k < sm.length; k++) {
      console.log(sm[k].toString())
    }
    
    let rand = await lottery.getRamd("3");
    console.log(rand[0].toString());
    console.log(rand[1].toString());
    console.log(rand[2].toString());
    console.log("--------------------------------------------------------------------------------------------------");
    let arr = await lottery.shuffle("1", rand[0].toString())
    // console.log(arr.length);
    for (var i = 0; i < arr.length; i++) {
      console.log(arr[i].toString());
    }
    console.log("--------------------------------------------------------------------------------------------------");
    arr2 = await lottery.shuffle("1", rand[1].toString())
    for (var j = 0; j < arr2.length; j++) {
      console.log(arr2[j].toString());
    }
  });
*/