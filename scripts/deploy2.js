const hre = require("hardhat");

const fDAIx = '0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f';

const main = async () => {
  const TestContract = await hre.ethers.getContractFactory("TestContract");
  const testContract = await TestContract.deploy(fDAIx);
  await testContract.deployed();

  console.log("TestContract deployed to:", testContract.address);
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
