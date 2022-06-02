const { expect } = require("chai");
const { ethers } = require("hardhat");

// To run on mainnet
// 1. Ensure you've using the correct TOKEN_0 & TOKEN_1 
// 2. run "npx hardhat node --fork https://eth-mainnet.alchemyapi.io/v2/{your alchemy key here}}"
// 3. open a second terminal and run "npx hardhat test --network localhost"

// To run on rinkeby
// 1. Ensure you've using the correct TOKEN_0 & TOKEN_1 
// 2. run "npx hardhat node --fork https://eth-rinkeby.alchemyapi.io/v2/{your alchemy key here}}"
// 3. open a second terminal and run "npx hardhat test --network localhost"

// fDAI address rinkeby //
const TOKEN_0 = "0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7"
// DAI address mainnet //
// const TOKEN_0 = "0x6B175474E89094C44Da98b954EedeAC495271d0F"

// wETH address rinkeby //
const TOKEN_1 = "0xc778417E063141139Fce010982780140Aa0cD5Ab"
// wrapped eth address mainnet //
// const TOKEN_1 = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

const DECIMALS_0 = 18n
const DECIMALS_1 = 18n

const V3FACTORYADDRESS = "0x1F98431c8aD98523631AE4a59f267346ea31F984"
const FEE = 3000

describe("UniswapV3PriceOracle", () => {
  it("get price", async () => {
    const UniswapV3Twap = await ethers.getContractFactory("UniswapV3PriceOracle");
    const twap = await UniswapV3Twap.deploy(V3FACTORYADDRESS, TOKEN_0, TOKEN_1, FEE);
    await twap.deployed();

    const amountOut = await twap.estimateAmountOut(TOKEN_1, 10n ** DECIMALS_1, 10);
    console.log(`amountOut: ${amountOut}`);

    const ethPrice = amountOut / 10 ** 18;
    console.log(`ETH price in DAI: ${ethPrice}`);
  });
});

