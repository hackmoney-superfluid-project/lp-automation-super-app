// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./ISuperToken.sol";
import "./ISETHProxy.sol";

contract TestMaticDowngrade {

    function getBalance(address tokenAddress) external returns (uint256) {
        ISuperToken token = ISuperToken(tokenAddress);
        uint256 balance = IERC20(token).balanceOf(address(this));
        return balance;
    }

    function downgradeMatic(address tokenAddress) external {
        ISuperToken token = ISuperToken(tokenAddress);
        //uint256 balance = IERC20(token).balanceOf(address(this));
        token.downgradeToETH(0);
        //token.upgradeByETH{value: address(this).balance}();
    }
}
