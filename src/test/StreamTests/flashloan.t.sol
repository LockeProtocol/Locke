// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.sol";

contract TestFlashloan is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);

        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
    }

    function test_flashloanTokenRevert() public {
        vm.expectRevert(IStream.BadERC20Interaction.selector);
        stream.flashloan(address(123), address(0), 100, "");
    }

    function test_flashloan() public {
        testTokenB.approve(address(stream), 1337);
        stream.stake(1337);

        uint256 currBal = testTokenB.balanceOf(address(this));

        stream.flashloan(address(testTokenB), address(this), 1337, abi.encode(true, currBal));

        assertTrue(enteredFlashloan);
    }
}
