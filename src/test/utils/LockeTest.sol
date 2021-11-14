// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../../Locke.sol";
import { TestHelpers } from "./HEVMHelpers.sol";
import "solmate/tokens/ERC20.sol";

contract User {
    constructor(address _ctrct) {
    }
}

abstract contract LockeTest is TestHelpers {
    // contracts
    StreamFactory defaultStreamFactory;


    ERC20 testTokenA;
    ERC20 testTokenB;

    // users
    User internal alice;
    User internal bob;

    function setUp() public virtual {
        testTokenA = new ERC20("Test Token A", "TTA", 18);
        testTokenB = new ERC20("Test Token B", "TTB", 18);

        write_balanceOf_ts(address(testTokenA), address(this), 100*10**18);
        write_balanceOf_ts(address(testTokenB), address(this), 100*10**18);
        assert(testTokenA.balanceOf(address(this)), 100*10**18);
        assert(testTokenB.balanceOf(address(this)), 100*10**18);

        defaultStreamFactory = new StreamFactory(address(this), address(this));
    }

    function createDefaultStream() public returns (Stream) {
        return defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            block.timestamp + 10, // 10 seconds in future
            4 weeks,
            26 weeks, // 6 months
            0,
            false
        );
    }
}
