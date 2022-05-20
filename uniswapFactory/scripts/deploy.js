const hre = require("hardhat");
const fs = require("fs");

const iNonfungiblePositionManagerAddress = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
const iSwapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564';

const main = async () => {
  const UniswapFactory = await hre.ethers.getContractFactory("UniswapFactory");
  const uniswapFactory = await UniswapFactory.deploy(iNonfungiblePositionManagerAddress, iSwapRouterAddress);
  await uniswapFactory.deployed();

  console.log("UniswapFactory deployed to:", uniswapFactory.address);
  fs.writeFileSync('currentAddress.js', `exports.uniswapFactoryAddress = "${uniswapFactory.address}"`);
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
