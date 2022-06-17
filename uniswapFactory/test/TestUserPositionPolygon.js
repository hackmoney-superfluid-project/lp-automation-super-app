const { expect } = require("chai");
const { ethers } = require("hardhat");
const IERC20 = artifacts.require("IERC20");
const IWMATIC = artifacts.require("IWMATIC");
const ISETH = artifacts.require("ISETH");
const ISwapRouter = artifacts.require("ISwapRouter");

const iNonfungiblePositionManagerAddress = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
const iSwapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
const iV3FactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
const MATICxAddress = '0x3aD736904E9e65189c3000c7DD2c8AC8bB7cD4e3';
const testWalletAddress = '0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245';
const testWalletAddress2 = '0x876EabF441B2EE5B5b0554Fd502a8E0600950cFa';

// test pair addresses
const MATICAddress = '0x0000000000000000000000000000000000000000';
const WETHAddress = '0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619';
const WMATICAddress = '0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270';

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
    let testWallet_Signer;
    let testWallet2_Signer;

    // runs before every test
    beforeEach(async function () {
        // get signers
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
        testWallet_Signer = await ethers.getSigner(testWalletAddress);
        testWallet_Signer2 = await ethers.getSigner(testWalletAddress2);

        // deploy price oracle
        PriceOracle = await ethers.getContractFactory("UniswapV3PriceOracle");
        deployedPriceOracle = await PriceOracle.deploy(iV3FactoryAddress);
        await deployedPriceOracle.deployed();

        // deploy UserPosition
        UserPosition = await ethers.getContractFactory("UserPosition");
        deployedUserPosition = await UserPosition.deploy(
            iNonfungiblePositionManagerAddress,
            MATICxAddress,
            testWalletAddress,
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
        })

        it("maintain position with a single LP position and sufficient funds", async function () {
            // wrap some of user's matic into MATICx
            const ISETH_MATICx_Contract = await ethers.getContractAt("ISETH", MATICxAddress);
            await ISETH_MATICx_Contract.connect(testWallet_Signer).upgradeByETH({value: '10000000000000000000'});

            // track user's initial balance of MATIC + WMATIC
            const MATICx_Contract = await ethers.getContractAt("IERC20", MATICxAddress);
            const WMATIC_Contract = await ethers.getContractAt("IERC20", WMATICAddress);
            const ib = Number(await ethers.provider.getBalance(testWalletAddress)) + Number(await WMATIC_Contract.balanceOf(testWalletAddress)) + Number(await MATICx_Contract.balanceOf(testWalletAddress))
            console.log('Users initial balance:' + ib );
            //console.log('Users initial maticX balance: ' + Number(await MATICx_Contract.balanceOf(testWalletAddress)) )

            // transfer funds
            await MATICx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, '200000000000000000');
            var MATICX_balanceOfContract = await MATICx_Contract.balanceOf(deployedUserPosition.address);
            expect(MATICX_balanceOfContract).to.equal('200000000000000000');

            // queue new position
            expect(await deployedUserPosition.getNumDeposits()).to.equal(0);
            await deployedUserPosition.connect(testWallet_Signer).orderNewUniswapV3LPDeposit(WMATICAddress, WETHAddress);
            expect(await deployedUserPosition.getNumDeposits()).to.equal(1);

            // test that maintainPosition():   1) doesn't revert   2) creates position / uses up all MATICx funds  3) contract gets uni v3 erc721 token
            var tx = await deployedUserPosition.connect(testWallet_Signer).maintainPosition();
            var rec = await tx.wait()
            console.log(rec.events?.filter((x) => {return x.event == "collectionAmounts"}))
            console.log(await deployedUserPosition.getDepositAmounts(WMATICAddress, WETHAddress))
            MATICX_balanceOfContract = await MATICx_Contract.balanceOf(deployedUserPosition.address);
            
            // test token balances
            const MATIC_Contract = await ethers.getContractAt("IERC20", MATICAddress);
            const WETH_Contract = await ethers.getContractAt("IERC20", WETHAddress);
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
            await MATICx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, '200000000000000000');
            MATICX_balanceOfContract = await MATICx_Contract.balanceOf(deployedUserPosition.address);
            expect(MATICX_balanceOfContract).to.equal('200000000000000000');
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
            //await deployedUserPosition.connect(testWallet_Signer).collectFees(WMATICAddress, WETHAddress, true);
            const wMaticBalanceAfterFees = await WMATIC_Contract.balanceOf(testWalletAddress);
            const wEthBalanceAfterFees = await WETH_Contract.balanceOf(testWalletAddress);
            const contract_wMaticBalanceAfterFees = await WMATIC_Contract.balanceOf(deployedUserPosition.address);
            const contract_wEthBalanceAfterFees = await WETH_Contract.balanceOf(deployedUserPosition.address);
            //expect(wMaticBalanceBeforeFees).to.equal(wMaticBalanceAfterFees);
            //expect(wEthBalanceBeforeFees).to.equal(wEthBalanceAfterFees);

            // perform swap on pair (simulate another user interacting with the pool) (have to wrap user's matic first)
            const iSwapRouter_Contract = await ethers.getContractAt("ISwapRouter", iSwapRouterAddress);
            const WMATIC_Deposit_Contract = await ethers.getContractAt("IWMATIC", WMATICAddress);
            const amountMaticToSwap = ( BigInt((await ethers.provider.getBalance(testWalletAddress2)) / 2) ).toString();
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
            console.log('out:' + await iSwapRouter_Contract.connect(testWallet_Signer2).exactInputSingle(swapParams));
            console.log(await deployedUserPosition.getDepositAmounts(WMATICAddress, WETHAddress))

            // collect fees again (expect increase in token balances)
            await deployedUserPosition.connect(testWallet_Signer).collectFees(WMATICAddress, WETHAddress, true);
            const wMaticBalanceAfterFees2 = await WMATIC_Contract.balanceOf(testWalletAddress);
            const wEthBalanceAfterFees2 = await WETH_Contract.balanceOf(testWalletAddress);
            const contract_wMaticBalanceAfterFees2 = await WMATIC_Contract.balanceOf(deployedUserPosition.address);
            const contract_wEthBalanceAfterFees2 = await WETH_Contract.balanceOf(deployedUserPosition.address);
            console.log('Users WMATIC balance diff: ' + (wMaticBalanceAfterFees2 - wMaticBalanceAfterFees));
            console.log('Users WETH balance diff: ' + (wEthBalanceAfterFees2 - wEthBalanceAfterFees));

            console.log('Contract WMATIC balance diff: ' + (contract_wMaticBalanceAfterFees2 - contract_wMaticBalanceAfterFees));
            console.log('Contract WETH balance diff: ' + (contract_wEthBalanceAfterFees2 - contract_wEthBalanceAfterFees));

            // test removing position
            console.log(await deployedUserPosition.getNumDeposits());
            tx = await deployedUserPosition.connect(testWallet_Signer).removeUniswapV3LPDeposit(WMATICAddress, WETHAddress);
            rec = await tx.wait()
            console.log(rec.events?.filter((x) => {return x.event == "collectionAmounts"}))
            console.log(rec.events?.filter((x) => {return x.event == "reportAddress"}))
            expect(await deployedUserPosition.getNumDeposits()).to.equal(0);

            const wMaticBalanceAfterRemoval = await WMATIC_Contract.balanceOf(testWalletAddress);
            const wEthBalanceAfterRemoval = await WETH_Contract.balanceOf(testWalletAddress);
            //console.log('Users WMATIC balance diff: ' + (wMaticBalanceAfterRemoval - wMaticBalanceAfterFees2));
            //console.log('Users WETH balance diff: ' + (wEthBalanceAfterRemoval - wEthBalanceAfterFees2));

            const fb = Number(await ethers.provider.getBalance(testWalletAddress)) + Number(await WMATIC_Contract.balanceOf(testWalletAddress)) + Number(await MATICx_Contract.balanceOf(testWalletAddress))
            console.log('Users final balance:' + fb );

            //console.log('Users final maticX balance: ' + Number(await MATICx_Contract.balanceOf(testWalletAddress)) )
        })
    })
})