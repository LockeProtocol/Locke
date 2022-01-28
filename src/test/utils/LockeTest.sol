// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "../../Locke.sol";
import "solmate/tokens/ERC20.sol";
import "./TestToken.sol";
import "forge-std/Vm.sol";
import "forge-std/stdlib.sol";
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

    function colorToString(Color color) internal returns (string memory s) {
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
    function emit_log_int(Color color, int a) internal {
        emit log_bytes(abi.encodePacked(colorToString(color), a, "\x1b[0m"));
    }
    function emit_log_uint(Color color, uint a) internal {
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
    function emit_log_named_decimal_int(Color color, string memory key, int val, uint decimals) internal {
        emit log_named_decimal_int(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val, decimals);
    }
    function emit_log_named_decimal_uint(Color color, string memory key, uint val, uint decimals) internal {
        emit log_named_decimal_uint(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val, decimals);
    }
    function emit_log_named_int(Color color, string memory key, int val) internal {
        emit log_named_int(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val);
    }
    function emit_log_named_uint(Color color, string memory key, uint val)  internal {
        emit log_named_uint(string(abi.encodePacked(colorToString(color), key, string("\x1b[0m"))), val);
    }
    function emit_log_named_bytes(Color color, string memory key, bytes memory val) internal {
        emit log_named_bytes(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val);
    }
    function emit_log_named_string(Color color, string memory key, string memory val)  internal{
        emit log_named_string(string(abi.encodePacked(colorToString(color), key, "\x1b[0m")), val);
    }
}

abstract contract LockeTest is DSTestPlus {
    using stdStorage for StdStorage;

    // contracts
    StreamFactory defaultStreamFactory;
    Vm vm = Vm(HEVM_ADDRESS);

    ERC20 testTokenA;
    ERC20 testTokenB;
    ERC20 testTokenC;

    StdStorage stdstore;

    uint160 nextUser = 1337;
    // users
    address alice;
    address bob;

    function setUp() public virtual {
        vm.warp(1609459200); // jan 1, 2021
        testTokenA = ERC20(address(new TestToken("Test Token A", "TTA", 18)));
        testTokenB = ERC20(address(new TestToken("Test Token B", "TTB", 18)));
        testTokenC = ERC20(address(new TestToken("Test Token C", "TTC", 18)));

        writeBalanceOf(address(this), address(testTokenA), 1<<128);
        writeBalanceOf(address(this), address(testTokenB), 1<<128);
        writeBalanceOf(address(this), address(testTokenC), 1<<128);

        assertEq(testTokenA.balanceOf(address(this)), 1<<128);
        assertEq(testTokenB.balanceOf(address(this)), 1<<128);
        assertEq(testTokenC.balanceOf(address(this)), 1<<128);

        defaultStreamFactory = new StreamFactory(address(this), address(this));

        alice = setupUser(true);
        bob = setupUser(true);
    }

    function setupUser(bool writeBalances) internal returns (address user) {
        user = address(nextUser);
        nextUser++;
        if (writeBalances) {
            writeBalanceOf(user, address(testTokenA), 1<<128);
            writeBalanceOf(user, address(testTokenB), 1<<128);
            writeBalanceOf(user, address(testTokenC), 1<<128);
        }
    }

    function writeBalanceOf(address who, address token, uint256 amt) internal {
        stdstore
            .target(token)
            .sig(testTokenA.balanceOf.selector)
            .with_key(who)
            .checked_write(amt);
    }

    function createDefaultStream() public returns (Stream) {
        return defaultStreamFactory.createStream(
            address(testTokenA),
            address(testTokenB),
            uint32(block.timestamp + 10), // 10 seconds in future
            4 weeks,
            26 weeks, // 6 months
            0,
            false
            // false,
            // bytes32(0)
        );
    }
}
