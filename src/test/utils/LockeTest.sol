// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../../Locke.sol";
import "./HEVMHelpers.sol";

contract User {
    constructor(address _ctrct) {
    }
}

abstract contract LockeTest is HEVMHelpers {
    // contracts

    // users
    User internal alice;
    User internal bob;

    function setUp() public virtual {
    }
}
