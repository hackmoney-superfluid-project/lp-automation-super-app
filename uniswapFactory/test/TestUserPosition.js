const { expect } = require("chai");
const { ethers } = require("hardhat");
const IERC20 = artifacts.require("IERC20");

const iNonfungiblePositionManagerAddress = '0xC36442b4a4522E871399CD717aBDD847Ab11FE88';
const iSwapRouterAddress = '0xE592427A0AEce92De3Edee1F18E0157C05861564';
const iV3FactoryAddress = '0x1F98431c8aD98523631AE4a59f267346ea31F984';
const fDAIxAddress = '0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90';
const testWalletAddress = '0xFc25b7BE2945Dd578799D15EC5834Baf34BA28e1';

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
            await fDAIx_Contract.connect(testWallet_Signer).transfer(deployedUserPosition.address, 1000);

            // TODO: queue new position

            // TODO: test that maintainPosition():   1) doesn't revert   2) creates position / uses up all fDAIx funds
        })
    })
})