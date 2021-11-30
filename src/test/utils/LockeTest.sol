// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../../Locke.sol";
import { TestHelpers } from "./TestHelpers.sol";
import "solmate/tokens/ERC20.sol";
import "./TestToken.sol";

contract User is TestHelpers{
    constructor() {
    }

    function doStake(Stream stream, address token, uint112 amount) public {
        write_balanceOf_ts(address(token), address(this), amount);
        ERC20(token).approve(address(stream), amount);
        stream.stake(amount);
    }

    function doWithdraw(Stream stream, uint112 amount) public {
        stream.withdraw(amount);
    }

    function doExit(Stream stream) public {
        stream.exit();
    }

    function doClaimReward(Stream stream) public {
        stream.claimReward();
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
        hevm.warp(1609459200); // jan 1, 2021
        testTokenA = ERC20(address(new TestToken("Test Token A", "TTA", 18)));
        testTokenB = ERC20(address(new TestToken("Test Token B", "TTB", 18)));
        write_balanceOf_ts(address(testTokenA), address(this), 100*10**18);
        write_balanceOf_ts(address(testTokenB), address(this), 100*10**18);
        assertEq(testTokenA.balanceOf(address(this)), 100*10**18);
        assertEq(testTokenB.balanceOf(address(this)), 100*10**18);

        defaultStreamFactory = new StreamFactory(address(this), address(this));

        alice = new User();
        bob = new User();

    }

    function createDefaultStream() public returns (Stream) {
        return defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + 10), // 10 seconds in future
            4 weeks,
            26 weeks, // 6 months
            0,
            false,
            false,
            bytes32(0)
        );
    }
}
