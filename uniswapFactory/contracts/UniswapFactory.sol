pragma solidity =0.7.6;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import './UserPosition.sol';
import './ISuperToken.sol';

contract UniswapFactory {

    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    ISwapRouter public immutable iSwapRouter;
    IUniswapV3Factory iV3Factory;
    address priceOracleAddress;

    // Not sure if we will need this:
    mapping(address => UserPosition) positions;

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISwapRouter _iSwapRouter,
        IUniswapV3Factory _iV3Factory,
        address _priceOracleAddress
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        iSwapRouter = _iSwapRouter;
        iV3Factory = _iV3Factory;
        priceOracleAddress = _priceOracleAddress;
    }

    function createUserPositionContract(ISuperToken acceptedToken, address userAddress) external returns (address) {
        UserPosition pos = new UserPosition(nonfungiblePositionManager, acceptedToken, userAddress, iSwapRouter, iV3Factory, priceOracleAddress);
        return address(pos);
    }

    function callPositionContract(address userAddress) external {
        // Take the address and call the respective position contracts function
        positions[userAddress].maintainPosition();
    }
}