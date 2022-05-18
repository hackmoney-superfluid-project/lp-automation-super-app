//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

contract TestContract {
    
    ISuperToken _acceptedToken;

    constructor(
        ISuperToken acceptedToken
    ) payable {
        _acceptedToken = acceptedToken;
    }

    function unwrap() public {
        _acceptedToken.downgrade(_acceptedToken.balanceOf(address(this)));
    }

}
