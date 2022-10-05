// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.15;

import "../utils/LockeTest.sol";

contract TestClaimReward is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (startTime, endStream, endDepositLock, endRewardLock) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenA), 1 << 128);
        writeBalanceOf(address(this), address(testTokenB), 1 << 128);
    }

    function test_claimRewardLockRevert() public {
        vm.expectRevert(IStream.LockOngoing.selector);
        stream.claimReward();
    }

    function test_claimOngoing() public {
        testTokenA.approve(address(stream), 1000);
        stream.fundStream(1000);

        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.warp(startTime + streamDuration / 2 + 1);

        stream.claimReward();

        {
            uint256 unstreamed = lens.currUnstreamed(stream);
            assertEq(unstreamed, 50);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));
            uint256 currTokens = lens.currDepositTokensNotYetStreamed(stream, address(this));
            // 1801 * 1000 * 10**18 // 3600 // 100
            assertEq(lastCumulativeRewardPerToken, 5002777777777777777);

            assertEq(virtualBalance, 100);
            assertEq(rewards, 0);
            assertEq(tokens, 50);
            assertEq(currTokens, 50);
            assertEq(lastUpdate, startTime + streamDuration / 2 + 1);
            assertTrue(!merkleAccess);
            assertEq(testTokenA.balanceOf(address(this)), uint256(1 << 128) - 500);
        }
    }

    function test_claimDelayed() public {
        vm.warp(startTime - 1);
        testTokenA.approve(address(stream), 1000);
        stream.fundStream(1000);

        vm.warp(startTime + streamDuration / 2 + 1);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.warp(startTime + streamDuration);

        stream.claimReward();
        stream.creatorClaim(address(this));

        {
            uint256 unstreamed = lens.currUnstreamed(stream);
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);

            assertEq(virtualBalance, 0);
            assertEq(rewards, 0);
            assertEq(tokens, 0);
            assertEq(lastUpdate, 0);
            assertTrue(!merkleAccess);
            // little bit of rounding
            assertEq(testTokenA.balanceOf(address(this)), 1 << 128);
        }
    }

    function test_claimPause() public {
        vm.warp(startTime - 1);
        testTokenA.approve(address(stream), 1000);
        stream.fundStream(1000);

        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.warp(startTime + streamDuration / 4 + 1);
        stream.exit();

        vm.warp(startTime + streamDuration * 2 / 4 + 1);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.warp(startTime + streamDuration);

        stream.claimReward();
        stream.rewardPerToken();
        stream.creatorClaim(address(this));

        {
            uint256 unstreamed = lens.currUnstreamed(stream);
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            // 1801 * 1000 * 10**18 // 3600 // 100
            assertEq(lastCumulativeRewardPerToken, 0);

            assertEq(virtualBalance, 0);
            assertEq(rewards, 0);
            assertEq(tokens, 0);
            assertEq(lastUpdate, 0);
            assertTrue(!merkleAccess);
            assertEq(testTokenA.balanceOf(address(this)), uint256(1 << 128) - 1);
        }
    }

    function test_claimEnd() public {
        testTokenA.approve(address(stream), 1000);
        stream.fundStream(1000);

        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.warp(startTime + streamDuration);

        stream.claimReward();
        stream.creatorClaim(address(this));
        {
            uint256 unstreamed = lens.currUnstreamed(stream);
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 0);
            assertEq(rewards, 0);
            assertEq(tokens, 0);
            assertEq(lastUpdate, 0);
            assertEq(stream.lastUpdate(), startTime + streamDuration);
            assertTrue(!merkleAccess);
            assertEq(testTokenA.balanceOf(address(this)), 1 << 128);
        }
    }

    function test_claimZeroRevert() public {
        testTokenA.approve(address(stream), 1000);
        stream.fundStream(1000);

        testTokenB.approve(address(stream), 100);
        stream.stake(100);
        vm.warp(startTime + streamDuration);

        stream.claimReward();
        stream.creatorClaim(address(this));

        {
            uint256 unstreamed = lens.currUnstreamed(stream);
            assertEq(unstreamed, 0);

            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(this));

            assertEq(lastCumulativeRewardPerToken, 0);
            assertEq(virtualBalance, 0);
            assertEq(rewards, 0);
            assertEq(tokens, 0);
            assertEq(lastUpdate, 0);
            assertEq(stream.lastUpdate(), startTime + streamDuration);
            assertTrue(!merkleAccess);
            assertEq(testTokenA.balanceOf(address(this)), 1 << 128);
        }

        vm.expectRevert(IStream.ZeroAmount.selector);
        stream.claimReward();
    }
}
