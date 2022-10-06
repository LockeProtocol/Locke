// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./utils/LockeTest.t.sol";
import "../src/interfaces/IStream.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";

contract Time {
    address creator;

    constructor() {
        creator = msg.sender;
    }

    modifier use() {
        Invariants(creator).use();
        _;
    }

    Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function advanceTime(uint8 warp) public use {
        vm.warp(block.timestamp + warp);
    }
}

contract User {
    IStream stream;
    address creator;

    using stdStorage for StdStorage;

    StdStorage stdstore;

    modifier use() {
        Invariants(creator).use();
        _;
    }

    constructor(IStream _stream) {
        stream = _stream;
        creator = msg.sender;
    }

    function writeBalanceOf(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(ERC20(token).balanceOf.selector).with_key(who).checked_write(amt);
    }

    function stake(uint96 amt) public use {
        address token = stream.depositToken();
        writeBalanceOf(address(this), token, amt);
        ERC20(token).approve(address(stream), uint256(amt));
        stream.stake(amt);
    }

    function withdraw(uint96 amt) public use {
        stream.withdraw(amt);
    }

    function exit() public use {
        stream.exit();
    }

    function fundStream(uint96 amt) public use {
        address token = stream.rewardToken();
        writeBalanceOf(address(this), token, amt);
        ERC20(token).approve(address(stream), uint256(amt));
        stream.fundStream(amt);
    }

    function creatorClaim() public use {
        Invariants(creator).creatorClaim();
    }

    function recoverTokens(address token) public use {
        Invariants(creator).recoverTokens(token);
    }

    function claimReward() public use {
        stream.claimReward();
    }
}

contract Invariants is BaseTest {
    address[] private _targetContracts;
    address[] private users;
    bool a;
    bool creatorClaimed;

    uint256 prev;
    uint256 uses = 1;

    function use() public {
        prev = uses;
        uses += 1;
    }

    function creatorClaim() public {
        creatorClaimed = true;
        stream.creatorClaim(address(this));
    }

    function recoverTokens(address token) public {
        stream.recoverTokens(token, address(this));
    }

    function setUp() public {
        tokenABC();
        setupInternal();
        stream = streamSetup(block.timestamp + minStartDelay);
        (startTime, endStream, endDepositLock, endRewardLock) = stream.streamParams();
        streamDuration = endStream - startTime;
        createUsers(5);
        for (uint256 i; i < 2; i++) {
            addTargetContract(address(new Time()));
        }
    }

    function createUsers(uint8 numUsers) internal {
        for (uint256 i; i < numUsers; i++) {
            User user = new User(stream);
            users.push(address(user));
            addTargetContract(address(user));
        }
    }

    function addTargetContract(address newTargetContract_) internal {
        _targetContracts.push(newTargetContract_);
    }

    function targetContracts() public view returns (address[] memory targetContracts_) {
        require(_targetContracts.length != uint256(0), "NO_TARGET_CONTRACTS");
        return _targetContracts;
    }

    function _receiptTokenInvariant() internal {
        if (!stream.isIndefinite()) {
            (, uint112 depositTokenAmount) = stream.tokenAmounts();
            uint256 internalBal = depositTokenAmount - stream.redeemedDepositTokens();
            assertEq(internalBal, LockeERC20(address(stream)).totalSupply());
            require(!failed(), "receipt token invariant");
        }
    }

    function _rewardInvariant() internal {
        (uint112 rewardTokenAmount,) = stream.tokenAmounts();
        uint256 actualStreamedTime = uint256(streamDuration - stream.unaccruedSeconds());
        uint256 actualRewards = actualStreamedTime * rewardTokenAmount / streamDuration;
        uint256 total_rewards = rewardTokenAmount - actualRewards;

        for (uint256 i; i < users.length; i++) {
            (,,,,, uint112 rewards) = stream.tokenStreamForAccount(users[i]);
            total_rewards += rewards;
        }

        assertLe(total_rewards, rewardTokenAmount, "Gave more away");
        require(!failed(), "reward invariant");
    }

    function _timeUpdateInvariant() internal {
        uint256 latest;
        for (uint256 i; i < users.length; i++) {
            (,,, uint32 lu,,) = stream.tokenStreamForAccount(users[i]);
            if (lu > latest) {
                latest = lu;
            }
        }

        // individual update invariant, may be less than because ts.lastUpdate may be set to 0 after claimReward & timestamp >= endStream
        if (latest != 0) {
            if (block.timestamp < endStream) {
                assertEq(latest, stream.lastUpdate());
            } else {
                assertLe(latest, stream.lastUpdate());
            }
        }
        require(!failed(), "lastupdate");
    }

    function _virtualBalanceInvariant() internal {
        if (block.timestamp < endStream) {
            uint256 totalVB;
            for (uint256 i; i < users.length; i++) {
                (, uint256 virtualBalance,,,,) = stream.tokenStreamForAccount(users[i]);
                totalVB += virtualBalance;
            }
            assertEq(totalVB, stream.totalVirtualBalance());
            require(!failed(), "virtual balance invariant");
        }
    }

    function invariant_rewards() public {
        require(uses > prev, "didnt use");
        // require(uses < 20, "didnt use");
        _rewardInvariant();
    }

    function invariant_time() public {
        require(uses > prev, "didnt use");
        // require(uses < 20, "didnt use");
        _timeUpdateInvariant();
    }

    function invariant_receiptToken() public {
        require(uses > prev, "didnt use");
        // require(uses < 20, "didnt use");
        _receiptTokenInvariant();
    }

    function invariant_virtualBalance() public {
        require(uses > prev, "didnt use");
        // require(uses < 20, "didnt use");
        _virtualBalanceInvariant();
    }
}
