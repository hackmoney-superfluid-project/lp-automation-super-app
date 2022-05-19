const hre = require("hardhat");

const host = '0xEB796bdb90fFA0f28255275e16936D25d3418603';
const fDAIx = '0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f';

// address to stream to here
const receiver = '0x41A10AFC05B4c18eF384c1cA88E5AC6c116cF7bE';

const main = async () => {
  const SuperAppPOC = await hre.ethers.getContractFactory("SuperAppPOC");
  const superAppPOC = await SuperAppPOC.deploy(host, fDAIx, receiver, '0x2feF0dBaeb0e29dBaf574d5FAA0f0110eCDa777a');
  await superAppPOC.deployed();

  console.log("SuperAppPOC deployed to:", superAppPOC.address);
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
