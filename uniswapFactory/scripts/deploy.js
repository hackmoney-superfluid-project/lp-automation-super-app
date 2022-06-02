const hre = require("hardhat");
const fs = require("fs");

const iNonfungiblePositionManagerAddress = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
const iSwapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
const iV3FactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984';

// fDAI
const TOKEN_0 = "0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7";
// wETH
const TOKEN_1 = "0xc778417E063141139Fce010982780140Aa0cD5Ab";

const fee = 3000;

const main = async () => {
  const UniswapV3PriceOracle = await hre.ethers.getContractFactory("UniswapV3PriceOracle");
  const uniswapV3PriceOracle = await UniswapV3PriceOracle.deploy(
    iV3FactoryAddress,
    TOKEN_0,
    TOKEN_1,
    fee);
  await uniswapV3PriceOracle.deployed();

  const UniswapFactory = await hre.ethers.getContractFactory("UniswapFactory");
  const uniswapFactory = await UniswapFactory.deploy(
    iNonfungiblePositionManagerAddress,
    iSwapRouterAddress,
    iV3FactoryAddress,
    uniswapV3PriceOracle.address);
  await uniswapFactory.deployed();

  console.log("UniswapFactory deployed to:", uniswapFactory.address);
  fs.writeFileSync('currentAddress.js', `exports.uniswapFactoryAddress = "${uniswapFactory.address}"`);
}

const runMain = async () => {
  try {
    await main();
    process.exit(0);
  } catch (error) {
    console.log('Error deploying contract: ', error);
    process.exit(1);
  }
}

runMain();

// address public constant mumbaiWETH = 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa;
// address public constant mumbaiMATICx = 0x96B82B65ACF7072eFEb00502F45757F254c2a0D4;
// address public constant mumbaiMATIC = 0x0000000000000000000000000000000000001010;
// address public constant mumbaiWMATIC = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;

// address public constant wETHOptimism = 0xbC6F6b680bc61e30dB47721c6D1c5cde19C1300d;
// address public constant fDAIOptimism = 0xbe49ac1EadAc65dccf204D4Df81d650B50122aB2;
// address public constant fDAIxOptimism = 0x04d4f73e9DE52a8fEC544087a66BBbA660A35957;

// address public constant fETHxRinkeby = 0xa623b2DD931C5162b7a0B25852f4024Db48bb1A0;
// address public constant wETHRinkeby = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
// address public constant fUNIRinkeby = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;