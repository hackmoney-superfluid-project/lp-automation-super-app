const hre = require("hardhat");

//const maticx = '0x96B82B65ACF7072eFEb00502F45757F254c2a0D4';

const main = async () => {
  const TestMaticDowngrade = await hre.ethers.getContractFactory("TestMaticDowngrade");
  const testMaticDowngrade = await TestMaticDowngrade.deploy();
  await testMaticDowngrade.deployed();

  console.log("TestMaticDowngrade deployed to:", testMaticDowngrade.address);
}

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log('Error deploying contract', error);
    process.exit(1);
  }
}

runMain();
