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

    // Not sure if we will need this:
    //mapping(address => UserPosition) positions;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager, ISwapRouter _iSwapRouter, IUniswapV3Factory _iV3Factory) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        iSwapRouter = _iSwapRouter;
        iV3Factory = _iV3Factory;
    }

    function createUserPositionContract(ISuperToken acceptedToken, address userAddress) external returns (address) {
        UserPosition pos = new UserPosition(nonfungiblePositionManager, acceptedToken, userAddress, iSwapRouter, iV3Factory);
        return address(pos);
    }
}