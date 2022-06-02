const { expect } = require("chai");
const { ethers } = require("hardhat");
const IERC20 = artifacts.require("IERC20");

const iNonfungiblePositionManagerAddress = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
const iSwapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
const iV3FactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
const fDAIxAddress = '0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90';
const testWalletAddress = '0x888D08001F91D0eEc2f16364779697462A9A713D';

// test pair addresses
const fDAIAddress = '0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7';
const WETHAddress = '0xc778417E063141139Fce010982780140Aa0cD5Ab';

// Uniswap V3 Positions NFT-V1 contract
const uniV3LPAddress = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
const fee = 3000;

describe("UserPosition Tests", function () {

    // global vars to be assigned in beforeEach
    let UserPosition;
    let deployedUserPosition;
    let owner;
    let addr1;
    let addr2;
    let addrs;

    // runs before every test
    beforeEach(async function () {
        // get signers
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

        // deploy price oracle
        PriceOracle = await ethers.getContractFactory("UniswapV3PriceOracle");
        deployedPriceOracle = await PriceOracle.deploy(iV3FactoryAddress, fDAIxAddress, WETHAddress, fee);
        await deployedPriceOracle.deployed();

        // deploy UserPosition
        UserPosition = await ethers.getContractFactory("UserPosition");
        deployedUserPosition = await UserPosition.deploy(
            iNonfungiblePositionManagerAddress,
            fDAIxAddress,
            owner.address,
            iSwapRouterAddress,
            iV3FactoryAddress,
            deployedPriceOracle.address);
        await deployedUserPosition.deployed();
    })

    describe("maintainPosition Tests", function () {
        it("maintain position with no positions and no funds", async function () {
            // just checking here that it doesn't revert
            for (let i = 0; i < 10; i++) {
                await deployedUserPosition.connect(owner).maintainPosition();
            }
        });

        it("downgrades super tokens successfully", async function () {
            // Arrange
            const fDAIx_Contract = await ethers.getContractAt("IERC20", fDAIxAddress);
            const fDAI_Contract = await ethers.getContractAt("IERC20", fDAIAddress);
            const testWallet_Signer = await ethers.getSigner(testWalletAddress);
            
            // Act
            await fDAIx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, 1000);
            await deployedUserPosition.connect(testWallet_Signer).orderNewUniswapV3LPDeposit(fDAIAddress, WETHAddress);
            await deployedUserPosition.connect(testWallet_Signer).maintainPosition();

            // Assert
            const fDAIContractBalance = await fDAI_Contract.balanceOf(deployedUserPosition.address);
            expect(fDAIContractBalance).to.equal(1000);
        });

        it("maintain position with a single LP position and sufficient funds", async function () {
            // transfer funds (just impersonating the fDAIx contract to take funds directly from it)
            const fDAIx_Contract = await ethers.getContractAt("IERC20", fDAIxAddress);
            const testWallet_Signer = await ethers.getSigner(testWalletAddress);
            await fDAIx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, 1000);
            var fDAIX_balanceOfContract = await fDAIx_Contract.balanceOf(deployedUserPosition.address);
            expect(fDAIX_balanceOfContract).to.equal(1000);

            // queue new position
            expect(await deployedUserPosition.getNumDeposits()).to.equal(0);
            await deployedUserPosition.connect(testWallet_Signer).orderNewUniswapV3LPDeposit(fDAIAddress, WETHAddress);
            expect(await deployedUserPosition.getNumDeposits()).to.equal(1);

            // test that maintainPosition():   1) doesn't revert   2) creates position / uses up all fDAIx funds  3) contract gets uni v3 erc721 token
            await deployedUserPosition.connect(testWallet_Signer).maintainPosition();
            fDAIX_balanceOfContract = await fDAIx_Contract.balanceOf(deployedUserPosition.address);
            
            // test token balances
            const fDAI_Contract = await ethers.getContractAt("IERC20", fDAIAddress);
            const fDAIContractBalance = await fDAI_Contract.balanceOf(deployedUserPosition.address);
            expect(fDAIContractBalance).to.equal(1000);
            
            const WETH_Contract = await ethers.getContractAt("IERC20", WETHAddress);
            const uniV3LP_Contract = await ethers.getContractAt("IERC20", uniV3LPAddress);
            expect(fDAIX_balanceOfContract).to.equal(0);
            console.log('fDAI balance: ' + await fDAI_Contract.balanceOf(deployedUserPosition.address));
            console.log('WETH balance: ' + await WETH_Contract.balanceOf(deployedUserPosition.address));
            console.log('UNI token balance: ' + await uniV3LP_Contract.balanceOf(deployedUserPosition.address));
            
            // Josh left off here: TODO: check these console.log values to test that position is minted properly
            // TODO: add expect() calls to check for specific values of each balanceOf
            // currently stuck at swapExactInputSingle(), was previously outputting 0 WETH (which then causes it to skip the position mint)
        })
    })
})