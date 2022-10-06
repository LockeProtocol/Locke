// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "../utils/LockeTest.t.sol";
import "../../src/interfaces/IMerkleStream.sol";

contract TestMerkleStake is BaseTest {
    bytes32 constant merkleRoot = 0x0cb3e761c847b0a2bd9e379b4ec584c83a23cff9e3a60e3782c10235e4f4690d;
    address approved = address(0x00a329c0648769A73afAc7F9381E08FB43dBEA72);

    function setUp() public {
        tokenAB();
        setupInternal();
        merkle = merkleStreamSetup(block.timestamp + minStartDelay, merkleRoot);
        (startTime, endStream, endDepositLock, endRewardLock) = merkle.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenA), 1 << 128);
        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
        writeBalanceOf(approved, address(testTokenB), 1 << 128);
        testTokenA.approve(address(merkle), type(uint256).max);
        uint112 amt = 1337;
        merkle.fundStream(amt);
    }

    function test_merkleStake() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = hex"a344aaf96e56d11c06dfb44729e931ae00ed3e67b4668eaacd6f5a88ebb48c70";
        vm.startPrank(approved);
        testTokenB.approve(address(merkle), 100);
        merkle.stake(100, proof);
    }

    function test_merkleStakeNoProof() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = hex"a344aaf96e56d11c06dfb44729e931ae00ed3e67b4668eaacd6f5a88ebb48c70";
        vm.startPrank(approved);
        testTokenB.approve(address(merkle), 200);
        merkle.stake(100, proof);

        merkle.stake(100);
    }

    function test_merkleStakeNoProofRevert() public {
        vm.startPrank(approved);
        testTokenB.approve(address(merkle), 200);
        vm.expectRevert(IMerkleStream.NoAccess.selector);
        merkle.stake(100);
    }

    function test_merkleStakeRevertAccess() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = hex"a344aaf96e56d11c06dfb44729e931ae00ed3e67b4668eaacd6f5a88ebb48c70";
        vm.startPrank(bob);
        testTokenB.approve(address(merkle), 100);
        vm.expectRevert(IMerkleStream.NoAccess.selector);
        merkle.stake(100, proof);
    }
}
