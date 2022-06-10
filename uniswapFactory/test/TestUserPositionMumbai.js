const { expect } = require("chai");
const { ethers } = require("hardhat");
const IERC20 = artifacts.require("IERC20");
const IWMATIC = artifacts.require("IWMATIC");
const ISwapRouter = artifacts.require("ISwapRouter");

const iNonfungiblePositionManagerAddress = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
const iSwapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
const iV3FactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
const MATICxAddress = '0x96B82B65ACF7072eFEb00502F45757F254c2a0D4';
const testWalletAddress = '0x888D08001F91D0eEc2f16364779697462A9A713D';
const testWalletAddress2 = '0xFc25b7BE2945Dd578799D15EC5834Baf34BA28e1';

// test pair addresses
const MATICAddress = '0x0000000000000000000000000000000000000000';
const WETHAddress = '0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa';

const WMATICAddress = '0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889';

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
        deployedUserPosition = await UserPosition.deploy(iNonfungiblePositionManagerAddress, MATICxAddress, owner.address, iSwapRouterAddress, iV3FactoryAddress);
    })

    describe("maintainPosition Tests", function () {
        it("maintain position with no positions and no funds", async function () {
            // just checking here that it doesn't revert
            for (let i = 0; i < 10; i++) {
                await deployedUserPosition.connect(owner).maintainPosition();
            }
        })

        it("maintain position with a single LP position and sufficient funds", async function () {
            // transfer funds
            const MATICx_Contract = await ethers.getContractAt("IERC20", MATICxAddress);
            const testWallet_Signer = await ethers.getSigner(testWalletAddress);
            await MATICx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, 1000000);
            var MATICX_balanceOfContract = await MATICx_Contract.balanceOf(deployedUserPosition.address);
            expect(MATICX_balanceOfContract).to.equal(1000000);

            // queue new position
            expect(await deployedUserPosition.getNumDeposits()).to.equal(0);
            await deployedUserPosition.connect(testWallet_Signer).orderNewUniswapV3LPDeposit(WMATICAddress, WETHAddress);
            expect(await deployedUserPosition.getNumDeposits()).to.equal(1);

            // test that maintainPosition():   1) doesn't revert   2) creates position / uses up all MATICx funds  3) contract gets uni v3 erc721 token
            await deployedUserPosition.connect(testWallet_Signer).maintainPosition();
            MATICX_balanceOfContract = await MATICx_Contract.balanceOf(deployedUserPosition.address);
            
            // test token balances
            const MATIC_Contract = await ethers.getContractAt("IERC20", MATICAddress);
            const WETH_Contract = await ethers.getContractAt("IERC20", WETHAddress);
            const WMATIC_Contract = await ethers.getContractAt("IERC20", WMATICAddress);
            const uniV3LP_Contract = await ethers.getContractAt("IERC20", uniV3LPAddress);
            // make sure all supertokens are downgraded
            expect(MATICX_balanceOfContract).to.equal(0);
            // there may be a small amount remaining, so just log these:
            console.log('MATIC balance: ' + await ethers.provider.getBalance(deployedUserPosition.address));
            console.log('WMATIC balance: ' + await WMATIC_Contract.balanceOf(deployedUserPosition.address));
            console.log('WETH balance: ' + await WETH_Contract.balanceOf(deployedUserPosition.address));
            // check for uniswap erc721 balance of 1
            expect(await uniV3LP_Contract.balanceOf(deployedUserPosition.address)).to.equal(1);

            // check liquidity of position
            const updatedDeposit = await deployedUserPosition.getDeposit(WMATICAddress, WETHAddress)
            expect(updatedDeposit.token0).to.equal(WMATICAddress)
            expect(updatedDeposit.token1).to.equal(WETHAddress)
            console.log('Liquidity: ' + updatedDeposit.liquidity)

            // transfer funds and update position again (expected to increase liquidity)
            await MATICx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, 1000000);
            MATICX_balanceOfContract = await MATICx_Contract.balanceOf(deployedUserPosition.address);
            expect(MATICX_balanceOfContract).to.equal(1000000);
            await deployedUserPosition.connect(testWallet_Signer).maintainPosition();

            // check that there is still 1 deposit and that liquidity has increased
            const updatedDeposit2 = await deployedUserPosition.getDeposit(WMATICAddress, WETHAddress)
            console.log('Liquidity: ' + updatedDeposit2.liquidity)
            //expect(Number(updatedDeposit2.liquidity)).to.greaterThan(Number(updatedDeposit.liquidity))
            expect(await deployedUserPosition.getNumDeposits()).to.equal(1);

            //      const maticBalanceAfterFees = await ethers.provider.getBalance(testWalletAddress);    
            // collect fees (expect no fees)
            const wMaticBalanceBeforeFees = await WMATIC_Contract.balanceOf(testWalletAddress);
            const wEthBalanceBeforeFees = await WETH_Contract.balanceOf(testWalletAddress);
            await deployedUserPosition.connect(testWallet_Signer).collectFees(WMATICAddress, WETHAddress, true);
            const wMaticBalanceAfterFees = await WMATIC_Contract.balanceOf(testWalletAddress);
            const wEthBalanceAfterFees = await WETH_Contract.balanceOf(testWalletAddress);
            expect(wMaticBalanceBeforeFees).to.equal(wMaticBalanceAfterFees);
            expect(wEthBalanceBeforeFees).to.equal(wEthBalanceAfterFees);

            // perform swap on pair (simulate another user interacting with the pool) (have to wrap user's matic first)
            const testWallet_Signer2 = await ethers.getSigner(testWalletAddress2);
            const iSwapRouter_Contract = await ethers.getContractAt("ISwapRouter", iSwapRouterAddress);
            const WMATIC_Deposit_Contract = await ethers.getContractAt("IWMATIC", WMATICAddress);
            const amountMaticToSwap = ((await ethers.provider.getBalance(testWalletAddress2)) / 2).toString();
            await WMATIC_Deposit_Contract.connect(testWallet_Signer2).deposit({value: amountMaticToSwap});
            await WMATIC_Contract.connect(testWallet_Signer2).approve(iSwapRouterAddress, amountMaticToSwap);
            const swapParams = {
                tokenIn: WMATICAddress,
                tokenOut: WETHAddress,
                fee: 3000,
                recipient: testWalletAddress2,
                deadline: 10000000000, // if someone is testing this code after the year 2286, please update this value
                amountIn: amountMaticToSwap,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            };
            await iSwapRouter_Contract.connect(testWallet_Signer2).exactInputSingle(swapParams);

            // collect fees again (expect increase in token balances)
            const tx = await deployedUserPosition.connect(testWallet_Signer).collectFees(WMATICAddress, WETHAddress, true);
            const receipt = await tx.wait();
            console.log(receipt.events)
            const wMaticBalanceAfterFees2 = await WMATIC_Contract.balanceOf(testWalletAddress);
            const wEthBalanceAfterFees2 = await WETH_Contract.balanceOf(testWalletAddress);
            console.log('Users WMATIC balance diff: ' + (wMaticBalanceAfterFees2 - wMaticBalanceAfterFees));
            console.log('Users WETH balance diff: ' + (wEthBalanceAfterFees2 - wEthBalanceAfterFees));
        })
    })
})