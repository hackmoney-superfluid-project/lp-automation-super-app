pragma solidity =0.7.6;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import './UserPosition.sol';
import './ISuperToken.sol';

contract UniswapFactory {

    INonfungiblePositionManager public immutable nonfungiblePositionManager;

    // Not sure if we will need this:
    //mapping(address => UserPosition) positions;

    constructor(INonfungiblePositionManager _nonfungiblePositionManager) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
    }

    function createUserPositionContract(ISuperToken acceptedToken, address userAddress) external returns (address) {
        UserPosition pos = new UserPosition(nonfungiblePositionManager, acceptedToken, userAddress);
        return address(pos);
    }
}