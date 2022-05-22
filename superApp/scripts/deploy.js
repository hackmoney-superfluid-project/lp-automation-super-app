const hre = require("hardhat");

// const host = '0xEB796bdb90fFA0f28255275e16936D25d3418603';
// const maticx = '0x96B82B65ACF7072eFEb00502F45757F254c2a0D4';
const host = '0xeD5B5b32110c3Ded02a07c8b8e97513FAfb883B6';
// const fETHx = '0xa623b2DD931C5162b7a0B25852f4024Db48bb1A0';
const fDAIx = '0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90';

// import address of uniswapFactory
const { uniswapFactoryAddress } = require("../../uniswapFactory/currentAddress.js");

const main = async () => {
  const SuperAppPOC = await hre.ethers.getContractFactory("SuperAppPOC");
  const superAppPOC = await SuperAppPOC.deploy(host, fDAIx, uniswapFactoryAddress);
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
