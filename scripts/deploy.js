const { BN, time } = require("@openzeppelin/test-helpers");
const { parseEther } = require("ethers/lib/utils");

async function main() {
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

  const busdAddress = "0x2774616c8B19C1D3E8802C6f802060f94494722f";
  let lottery = await PancakeSwapLottery.deploy(busdAddress, randomNumberGenerator.address);

  await lottery.deployed();
  console.log("PancakeSwapLottery deployed to:", lottery.address);

  // Set lottery address
  await randomNumberGenerator.setLotteryAddress(lottery.address);
  console.log("PancakeSwapLottery address added to randomNumberGenerator");
  // Set operator & treasury adresses
  await lottery.setOperatorAndTreasuryAndInjectorAddresses(
    deployer.address,
    deployer.address,
    deployer.address,
  );
  // console.log("wait for transaction");
  // await new Promise(r => setTimeout(r, 30000));

  console.log("PancakeSwapLottery injectorAddress");
  console.log(await lottery.injectorAddress());
  console.log("PancakeSwapLottery operatorAddress");
  console.log(await lottery.operatorAddress());
  console.log("PancakeSwapLottery treasuryAddress");
  console.log(await lottery.treasuryAddress());
  /*
  let _lengthLottery = new BN("43200"); // 4h
  endTime = new BN(await time.latest()).add(_lengthLottery);
  let _priceTicketInCake = parseEther("200");

  let _minTicketsToSell = "500";
  let _maxTicketsToSell = "1500";
  let _prizes = [parseEther("60000"), parseEther("25000"), parseEther("15000")];
  let _referralReward = "500";

  await lottery.connect(deployer).startLottery(
    "1651928464",
    _priceTicketInCake,
    _minTicketsToSell,
    _maxTicketsToSell,
    _prizes,
    _referralReward,
  );
  console.log("lottery started");
  */
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });