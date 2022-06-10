// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";

/**
 * @title Super token (Superfluid Token + ERC20 + ERC777) interface
 * @author Superfluid
 */
interface ISuperToken is IERC20, IERC777 {

    function totalSupply() external view override(IERC777, IERC20) returns (uint256);

    function balanceOf(address account) external view override(IERC777, IERC20) returns(uint256 balance);

    function transferAll(address recipient) external;

    function getUnderlyingToken() external view returns(address tokenAddr);

    function upgrade(uint256 amount) external;

    function downgrade(uint256 amount) external;
}