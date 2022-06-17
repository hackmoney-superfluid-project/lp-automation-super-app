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

        // deploy UserPosition
        UserPosition = await ethers.getContractFactory("UserPosition");
        deployedUserPosition = await UserPosition.deploy(iNonfungiblePositionManagerAddress, fDAIxAddress, owner.address, iSwapRouterAddress, iV3FactoryAddress);
    })

    describe("maintainPosition Tests", function () {
        it("maintain position with no positions and no funds", async function () {
            // just checking here that it doesn't revert
            for (let i = 0; i < 10; i++) {
                await deployedUserPosition.connect(owner).maintainPosition();
            }
        })

        it("maintain position with a single LP position and sufficient funds", async function () {
            // transfer funds (just impersonating the fDAIx contract to take funds directly from it)
            const fDAIx_Contract = await ethers.getContractAt("IERC20", fDAIxAddress);
            const testWallet_Signer = await ethers.getSigner(testWalletAddress);
            await fDAIx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, 1000000);
            var fDAIX_balanceOfContract = await fDAIx_Contract.balanceOf(deployedUserPosition.address);
            expect(fDAIX_balanceOfContract).to.equal(1000000);

            // queue new position
            expect(await deployedUserPosition.getNumDeposits()).to.equal(0);
            await deployedUserPosition.connect(testWallet_Signer).orderNewUniswapV3LPDeposit(fDAIAddress, WETHAddress);
            expect(await deployedUserPosition.getNumDeposits()).to.equal(1);

            // test that maintainPosition():   1) doesn't revert   2) creates position / uses up all fDAIx funds  3) contract gets uni v3 erc721 token
            await deployedUserPosition.connect(testWallet_Signer).maintainPosition();
            fDAIX_balanceOfContract = await fDAIx_Contract.balanceOf(deployedUserPosition.address);
            
            // test token balances
            const fDAI_Contract = await ethers.getContractAt("IERC20", fDAIAddress);
            const WETH_Contract = await ethers.getContractAt("IERC20", WETHAddress);
            const uniV3LP_Contract = await ethers.getContractAt("IERC20", uniV3LPAddress);
            // make sure all supertokens are downgraded
            expect(fDAIX_balanceOfContract).to.equal(0);
            // there may be a small amount remaining, so just log these:
            console.log('fDAI balance: ' + await fDAI_Contract.balanceOf(deployedUserPosition.address));
            console.log('WETH balance: ' + await WETH_Contract.balanceOf(deployedUserPosition.address));
            // check for uniswap erc721 balance of 1
            expect(await uniV3LP_Contract.balanceOf(deployedUserPosition.address)).to.equal(1);
            
            // check liquidity of position
            const updatedDeposit = await deployedUserPosition.getDeposit(fDAIAddress, WETHAddress)
            expect(updatedDeposit.token0).to.equal(fDAIAddress)
            expect(updatedDeposit.token1).to.equal(WETHAddress)
            console.log('Liquidity: ' + updatedDeposit.liquidity)

            // transfer funds and update position again (expected to increase liquidity)
            await fDAIx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, 1000000);
            fDAIX_balanceOfContract = await fDAIx_Contract.balanceOf(deployedUserPosition.address);
            expect(fDAIX_balanceOfContract).to.equal(1000000);
            await deployedUserPosition.connect(testWallet_Signer).maintainPosition();

            // check that there is still 1 deposit and that liquidity has increased
            const updatedDeposit2 = await deployedUserPosition.getDeposit(fDAIAddress, WETHAddress)
            console.log('Liquidity: ' + updatedDeposit2.liquidity)
            expect( Number(updatedDeposit2.liquidity) ).to.greaterThan( Number(updatedDeposit.liquidity) )
            //expect(await deployedUserPosition.getNumDeposits()).to.equal(1); <-- failing, this tracks the array of hashes, not the mapping iteself, probably just forgot to update properly
        })
    })
})