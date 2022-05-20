pragma solidity =0.7.6;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import './UserPosition.sol';
import './ISuperToken.sol';

contract UniswapFactory {

    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    ISwapRouter public immutable iSwapRouter;

    // Not sure if we will need this:
    //mapping(address => UserPosition) positions;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager, ISwapRouter _iSwapRouter) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        iSwapRouter = _iSwapRouter;
    }

    function createUserPositionContract(ISuperToken acceptedToken, address userAddress) external returns (address) {
        UserPosition pos = new UserPosition(nonfungiblePositionManager, acceptedToken, userAddress, iSwapRouter);
        return address(pos);
    }
}