pragma solidity 0.8.11;

import "../utils/LockeTest.sol";

contract TestCreatorClaimTokens is BaseTest {
    function setUp() public {
        tokenAB();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        indefinite = streamSetupIndefinite(block.timestamp + minStartDelay);

        (
            startTime,
            endStream,
            endDepositLock,
            endRewardLock
        ) = stream.streamParams();
        streamDuration = endStream - startTime;

        writeBalanceOf(address(this), address(testTokenA), 1<<128);
        writeBalanceOf(address(this), address(testTokenB), 1<<128);
    }

    function test_creatorClaimTokensLeftovers() public {
        testTokenA.approve(address(stream), 1000);
        stream.fundStream(1000);

        vm.warp(startTime + streamDuration/2);
        testTokenB.approve(address(stream), 100);
        stream.stake(100);

        vm.warp(endDepositLock + 1);
        stream.claimReward();
        stream.creatorClaim(address(this));
        assertEq(testTokenA.balanceOf(address(stream)), 0);
    }

    function test_creatorClaimTokensDoubleClaimRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.warp(endDepositLock + 1);
        indefinite.creatorClaim(address(this));

        vm.expectRevert(Stream.BalanceError.selector);
        indefinite.creatorClaim(address(this));
    }

    function test_creatorClaimTokensCreatorRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.warp(endDepositLock + 1);

        vm.expectRevert(Stream.NotCreator.selector);
        vm.prank(alice);
        indefinite.creatorClaim(address(this));
    }

    function test_creatorClaimTokensStreamRevert() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.expectRevert(Stream.StreamOngoing.selector);
        indefinite.creatorClaim(address(this));
    }

    function test_creatorClaimTokens() public {
        testTokenB.approve(address(indefinite), 100);
        indefinite.stake(100);

        vm.warp(endDepositLock + 1);

        uint256 preBal = testTokenB.balanceOf(address(this));

        indefinite.creatorClaim(address(this));
        
        assertEq(testTokenB.balanceOf(address(this)), preBal + 100);

        uint256 redeemed = uint256(vm.load(address(indefinite), bytes32(uint256(10)))) >> 112;
        assertEq(redeemed, 100);

        uint8 claimed = uint8(uint256(vm.load(address(indefinite), bytes32(uint256(7)))) >> (112 + 112 + 8));
        assertEq(claimed, 1);
    }
}