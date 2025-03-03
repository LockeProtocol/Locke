// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../src/interfaces/IStreamFactory.sol";
import "../../src/interfaces/IStream.sol";
import "../../src/interfaces/IMerkleStream.sol";

import "../../src/Locke.sol";
import "../../src/MerkleLocke.sol";
import "../../src/LockeFactory.sol";
import "../../src/LockeLens.sol";
import "solmate/tokens/ERC20.sol";
import "./TestToken.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "ds-test/test.sol";

contract DSTestPlus is DSTest {
    enum Color {
        Black,
        Blue,
        Green,
        Cyan,
        Red,
        Purple,
        Brown,
        Gray,
        DarkGray,
        LightBlue,
        LightGreen,
        LightCyan,
        LightRed,
        LightPurple,
        Yellow,
        White
    }

    function colorToString(Color color) internal pure returns (string memory s) {
        assembly {
            mstore(s, 0x08)
            switch color
            case 0 { mstore(add(s, 0x20), "\x1b[0;30m ") }
            case 1 { mstore(add(s, 0x20), "\x1b[0;34m ") }
            case 2 { mstore(add(s, 0x20), "\x1b[0;32m ") }
            case 3 { mstore(add(s, 0x20), "\x1b[0;36m ") }
            case 4 { mstore(add(s, 0x20), "\x1b[0;31m ") }
            case 5 { mstore(add(s, 0x20), "\x1b[0;35m ") }
            case 6 { mstore(add(s, 0x20), "\x1b[0;33m ") }
            case 7 { mstore(add(s, 0x20), "\x1b[0;37m ") }
            case 8 { mstore(add(s, 0x20), "\x1b[1;30m ") }
            case 9 { mstore(add(s, 0x20), "\x1b[1;34m ") }
            case 10 { mstore(add(s, 0x20), "\x1b[1;32m ") }
            case 11 { mstore(add(s, 0x20), "\x1b[1;36m ") }
            case 12 { mstore(add(s, 0x20), "\x1b[1;31m ") }
            case 13 { mstore(add(s, 0x20), "\x1b[1;35m ") }
            case 14 { mstore(add(s, 0x20), "\x1b[1;33m ") }
            case 15 { mstore(add(s, 0x20), "\x1b[1;37m ") }
        }
    }

    function emit_log(Color color, string memory a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }

    function emit_logs(Color color, bytes memory a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }

    function emit_log_address(Color color, address a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }

    function emit_log_bytes32(Color color, bytes32 a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }

    function emit_log_int(Color color, int256 a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }

    function emit_log_uint(Color color, uint256 a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }

    function emit_log_bytes(Color color, bytes memory a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }

    function emit_log_string(Color color, string memory a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }

    function emit_log_named_address(Color color, string memory key, address val) internal {
        emit log_named_address(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val);
    }

    function emit_log_named_bytes32(Color color, string memory key, bytes32 val) internal {
        emit log_named_bytes32(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val);
    }

    function emit_log_named_decimal_int(Color color, string memory key, int256 val, uint256 decimals) internal {
        emit log_named_decimal_int(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val, decimals);
    }

    function emit_log_named_decimal_uint(Color color, string memory key, uint256 val, uint256 decimals) internal {
        emit log_named_decimal_uint(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val, decimals);
    }

    function emit_log_named_int(Color color, string memory key, int256 val) internal {
        emit log_named_int(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val);
    }

    function emit_log_named_uint(Color color, string memory key, uint256 val) internal {
        emit log_named_uint(string(abi.encodePacked(colorToString(color), key, string("\x1b[0m"))), val);
    }

    function emit_log_named_bytes(Color color, string memory key, bytes memory val) internal {
        emit log_named_bytes(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val);
    }

    function emit_log_named_string(Color color, string memory key, string memory val) internal {
        emit log_named_string(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val);
    }

    function assertRelApproxEq(uint256 a, uint256 b, uint256 maxPercentDelta) internal virtual {
        uint256 delta = a > b ? a - b : b - a;
        if (delta == 0) {
            return;
        }

        uint256 abs = a > b ? a : b;

        uint256 percentDelta = (delta * 1e18) / abs;

        if (percentDelta > maxPercentDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("    Expected", a);
            emit log_named_uint("      Actual", b);
            emit log_named_uint(" Max % Delta", maxPercentDelta);
            emit log_named_uint("     % Delta", percentDelta);
            fail();
        }
    }
}

abstract contract BaseTest is DSTestPlus {
    using stdStorage for StdStorage;

    // ==== Testing ====
    StdStorage stdstore;
    Vm vm = Vm(HEVM_ADDRESS);
    uint160 nextUser = 1337;
    // users
    address alice;
    address bob;

    LockeLens lens;

    ERC20 testTokenA;
    ERC20 testTokenB;
    ERC20 testTokenC;
    // =================

    bool enteredFlashloan = false;

    IStreamFactory defaultStreamFactory;
    IStream stream;
    IStream fee;
    IStream indefinite;
    IMerkleStream merkle;

    uint32 maxDepositLockDuration;
    uint32 maxRewardLockDuration;
    uint32 maxStreamDuration;
    uint32 minStreamDuration;
    uint32 minStartDelay;

    uint32 startTime;
    uint32 endStream;
    uint32 endDepositLock;
    uint32 endRewardLock;

    uint32 streamDuration;

    function checkState() internal {
        require(!failed(), "other");

        BaseTest(address(this)).rewardInvariant();
        BaseTest(address(this)).timeUpdateInvariant();
        BaseTest(address(this)).virtualBalanceInvariant();
        BaseTest(address(this)).receiptTokenInvariant();
    }

    function receiptTokenInvariant() public {
        if (!stream.isIndefinite()) {
            (, uint112 depositTokenAmount) = stream.tokenAmounts();
            uint256 internalBal = depositTokenAmount - stream.redeemedDepositTokens();
            assertEq(internalBal, LockeERC20(address(stream)).totalSupply());
            require(!failed(), "receipt token invariant");
        }
    }

    function rewardInvariant() public {
        (,,,,, uint112 rewardsA) = stream.tokenStreamForAccount(alice);
        (,,,,, uint112 rewardsB) = stream.tokenStreamForAccount(bob);
        (,,,,, uint112 rewards) = stream.tokenStreamForAccount(address(this));
        (uint112 rewardTokenAmount,) = stream.tokenAmounts();
        assertLe(rewardsA + rewardsB + rewards, rewardTokenAmount, "Gave more away");
        require(!failed(), "reward invariant");
    }

    function timeUpdateInvariant() public {
        (,,, uint32 luA,,) = stream.tokenStreamForAccount(alice);
        (,,, uint32 luB,,) = stream.tokenStreamForAccount(bob);
        (,,, uint32 lu,,) = stream.tokenStreamForAccount(address(this));
        uint32 max3 = luA > luB ? luA : luB;
        max3 = max3 > lu ? max3 : lu;

        // individual update invariant, may be less than because ts.lastUpdate may be set to 0 after claimReward & timestamp >= endStream
        if (max3 != 0) {
            if (block.timestamp < endStream) {
                assertEq(max3, stream.lastUpdate());
            } else {
                assertLe(max3, stream.lastUpdate());
            }
        }
        require(!failed(), "lastupdate");
    }

    function virtualBalanceInvariant() public {
        if (block.timestamp < endStream) {
            (, uint256 virtualBalanceA,,,,) = stream.tokenStreamForAccount(alice);
            (, uint256 virtualBalanceB,,,,) = stream.tokenStreamForAccount(bob);
            (, uint256 virtualBalance,,,,) = stream.tokenStreamForAccount(address(this));
            assertEq(virtualBalanceA + virtualBalanceB + virtualBalance, stream.totalVirtualBalance());
            require(!failed(), "virtual balance invariant");
        }
    }

    function setupUser(bool writeBalances) internal returns (address user) {
        user = address(nextUser);
        nextUser++;
        if (writeBalances) {
            writeBalanceOf(user, address(testTokenA), 1 << 128);
            writeBalanceOf(user, address(testTokenB), 1 << 128);
            writeBalanceOf(user, address(testTokenC), 1 << 128);
        }
    }

    function writeBalanceOf(address who, address token, uint256 amt) internal {
        stdstore.target(token).sig(testTokenA.balanceOf.selector).with_key(who).checked_write(amt);
    }

    function createDefaultStream() public returns (IStream) {
        return defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + 10), // 10 seconds in future
            4 weeks,
            26 weeks, // 6 months
            0,
            false // false,
                // bytes32(0)
        );
    }

    function lockeCall(address, /*originator*/ address token, uint256 amount, bytes memory data) external {
        (bool sendBackFee, uint256 prevBal) = abi.decode(data, (bool, uint256));
        assertEq(ERC20(token).balanceOf(address(this)), prevBal + amount);
        if (sendBackFee) {
            ERC20(token).transfer(msg.sender, amount * 10 / 10000);
        }
        ERC20(token).transfer(msg.sender, amount);
        enteredFlashloan = true;
        return;
    }

    function setupInternal() public {
        vm.warp(1640995200); // jan 1, 2022
        vm.label(address(this), "TestContract");
        alice = address(nextUser);
        vm.label(alice, "Alice");
        nextUser++;
        bob = address(nextUser);
        vm.label(bob, "Bob");
        StreamCreation externalCreate = new StreamCreation();
        MerkleStreamCreation externalCreate2 = new MerkleStreamCreation();
        defaultStreamFactory = new StreamFactory(externalCreate, externalCreate2);

        (
            uint32 _maxDepositLockDuration,
            uint32 _maxRewardLockDuration,
            uint32 _maxStreamDuration,
            uint32 _minStreamDuration,
            uint32 _minStartDelay
        ) = defaultStreamFactory.streamCreationParams();
        maxDepositLockDuration = _maxDepositLockDuration;
        maxRewardLockDuration = _maxRewardLockDuration;
        maxStreamDuration = _maxStreamDuration;
        minStreamDuration = _minStreamDuration;
        minStartDelay = _minStartDelay;

        lens = new LockeLens();

        vm.label(address(lens), "Lens");
    }

    function streamSetup(uint256 _startTime) internal returns (IStream _stream) {
        (uint32 i_maxDepositLockDuration,,, uint32 i_minStreamDuration,) = defaultStreamFactory.streamCreationParams();

        _stream = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(_startTime), // 10 seconds in future
            i_minStreamDuration,
            i_maxDepositLockDuration,
            0,
            false // false,
                // bytes32(0)
        );
        vm.label(address(_stream), "Stream");
    }

    function merkleStreamSetup(uint256 _startTime, bytes32 root) internal returns (IMerkleStream _merkle) {
        (uint32 i_maxDepositLockDuration,,, uint32 i_minStreamDuration,) = defaultStreamFactory.streamCreationParams();

        _merkle = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(_startTime), // 10 seconds in future
            i_minStreamDuration,
            i_maxDepositLockDuration,
            0,
            false,
            root // false,
                // bytes32(0)
        );
        vm.label(address(_merkle), "MerkleStream");
    }

    function streamSetupIndefinite(uint256 _startTime) internal returns (IStream _stream) {
        (uint32 i_maxDepositLockDuration,,, uint32 i_minStreamDuration,) = defaultStreamFactory.streamCreationParams();

        _stream = defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(_startTime), // 10 seconds in future
            i_minStreamDuration,
            i_maxDepositLockDuration,
            0,
            true // false,
                // bytes32(0)
        );

        vm.label(address(_stream), "Indefinite");
    }

    function tokenA() public {
        testTokenA = ERC20(address(new TestToken("Test Token A", "TTA", 18)));
        vm.label(address(testTokenA), "TestTokenA");
    }

    function tokenAB() public {
        testTokenA = ERC20(address(new TestToken("Test Token A", "TTA", 18)));
        testTokenB = ERC20(address(new TestToken("Test Token B", "TTB", 18)));
        vm.label(address(testTokenA), "TestTokenA");
        vm.label(address(testTokenB), "TestTokenB");
    }

    function tokenABC() public {
        testTokenA = ERC20(address(new TestToken("Test Token A", "TTA", 18)));
        testTokenB = ERC20(address(new TestToken("Test Token B", "TTB", 18)));
        testTokenC = ERC20(address(new TestToken("Test Token C", "TTC", 18)));
        vm.label(address(testTokenA), "TestTokenA");
        vm.label(address(testTokenB), "TestTokenB");
        vm.label(address(testTokenC), "TestTokenC");
    }
}
