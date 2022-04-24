const { BN, time } = require("@openzeppelin/test-helpers");
const { parseEther } = require("ethers/lib/utils");

async function main() {
  // let acc = await ethers.getSigners()
  // console.log(await acc[1].getAddress());
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  console.log("Account balance:", (await deployer.getBalance()).toString());
  
  const PancakeSwapLottery = await ethers.getContractFactory("PancakeSwapLottery");

  let randomNumberGenerator;
  console.log("RandomNumberGenerator with VRF is deployed..");
  const RandomNumberGenerator = await ethers.getContractFactory("RandomNumberGenerator");

  randomNumberGenerator = await RandomNumberGenerator.deploy(
    "0xa555fC018435bef5A13C6c6870a9d4C11DEC329C",
    "0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06"
  );
  await randomNumberGenerator.deployed();
  console.log("RandomNumberGenerator deployed to:", randomNumberGenerator.address);

  // Set fee
  await randomNumberGenerator.setFee("100000000000000000");

  // Set key hash
  await randomNumberGenerator.setKeyHash("0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186");

  const tusdAddress = "0xE35282d31014C1534EbB4689D7596AaF2CEB8f3D";
  let lottery = await PancakeSwapLottery.deploy(tusdAddress, randomNumberGenerator.address);

  await lottery.deployed();
  console.log("PancakeSwapLottery deployed to:", lottery.address);

  // Set lottery address
  await randomNumberGenerator.setLotteryAddress(lottery.address);
  console.log("PancakeSwapLottery address added to randomNumberGenerator");
  // Set operator & treasury adresses
  await lottery.setOperatorAndTreasuryAndInjectorAddresses(
    deployer.address,
    deployer.address,
    deployer.address
  );

  console.log("PancakeSwapLottery injectorAddress");
  console.log(await lottery.injectorAddress());
  console.log("PancakeSwapLottery operatorAddress");
  console.log(await lottery.operatorAddress());
  console.log("PancakeSwapLottery treasuryAddress");
  console.log(await lottery.treasuryAddress());

  let _lengthLottery = new BN("14400"); // 4h
  endTime = new BN(await time.latest()).add(_lengthLottery);
  let _priceTicketInCake = parseEther("0.5");
  let _discountDivisor = "2000";
  let _rewardsBreakdown = ["200", "300", "500", "1500", "2500", "5000"];
  let _treasuryFee = "2000";

  await lottery.connect(deployer).startLottery(
    "1650837791",
    _priceTicketInCake,
    _discountDivisor,
    _rewardsBreakdown,
    _treasuryFee
  );
  console.log("lottery started");

  // await lottery.buyTickets("1", ["1234561", "1234562"])
  // console.log("tickets bought");

  /*
    Deploying contracts with the account: 0xF828ed422df798e055d539C2DB6eE11ee626E384
    Account balance: 900645080000000000
    RandomNumberGenerator with VRF is deployed..
    RandomNumberGenerator deployed to: 0xa5CaaC5fe696b71621D9BbE974496EDB73f2a714
    PancakeSwapLottery deployed to: 0xC1648379EC98d40fD55313d2Ae1d009d47DFf814
    PancakeSwapLottery address added to randomNumberGenerator
    PancakeSwapLottery injectorAddress
    0x0000000000000000000000000000000000000000
    PancakeSwapLottery operatorAddress
    0x0000000000000000000000000000000000000000
    PancakeSwapLottery treasuryAddress
    0x0000000000000000000000000000000000000000
  */
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });