// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "solmate/tokens/ERC20.sol";
import "./interfaces/ILockeERC20.sol";
import "./SharedState.sol";

library DateTime {
    uint256 private constant MAX_UINT256_STRING_LENGTH = 78;
    uint8 private constant ASCII_DIGIT_OFFSET = 48;

    /// @dev Converts a `uint256` value to a string.
    /// @param n The integer to convert.
    /// @return nstr `n` as a decimal string.
    function toString(uint256 n) public pure returns (string memory nstr) {
        if (n == 0) {
            return "0";
        }
        // Overallocate memory
        nstr = new string(MAX_UINT256_STRING_LENGTH);
        uint256 k = MAX_UINT256_STRING_LENGTH;
        // Populate string from right to left (lsb to msb).
        while (n != 0) {
            assembly {
                let char := add(ASCII_DIGIT_OFFSET, mod(n, 10))
                mstore(add(nstr, k), char)
                k := sub(k, 1)
                n := div(n, 10)
            }
        }
        assembly {
            // Shift pointer over to actual start of string.
            nstr := add(nstr, k)
            // Store actual string length.
            mstore(nstr, sub(MAX_UINT256_STRING_LENGTH, k))
        }
        return nstr;
    }

    function _monthToString(uint256 month) internal pure returns (string memory s) {
        assembly {
            // grab freemem
            let sp := mload(0x40)
            // set length
            mstore(sp, 0x03)
            // update freemem
            mstore(0x40, add(sp, 0x40))
            // set string content
            switch month
            case 1 { mstore(add(sp, 0x20), "JAN") }
            case 2 { mstore(add(sp, 0x20), "FEB") }
            case 3 { mstore(add(sp, 0x20), "MAR") }
            case 4 { mstore(add(sp, 0x20), "APR") }
            case 5 { mstore(add(sp, 0x20), "MAY") }
            case 6 { mstore(add(sp, 0x20), "JUN") }
            case 7 { mstore(add(sp, 0x20), "JUL") }
            case 8 { mstore(add(sp, 0x20), "AUG") }
            case 9 { mstore(add(sp, 0x20), "SEP") }
            case 10 { mstore(add(sp, 0x20), "OCT") }
            case 11 { mstore(add(sp, 0x20), "NOV") }
            case 12 { mstore(add(sp, 0x20), "DEC") }
            // set return value as ptr to string
            s := sp
        }
    }

    function daysToDate(uint256 _days) public pure returns (string memory datetime) {
        int256 __days = int256(_days);

        int256 L = __days + 68569 + 2440588;
        int256 N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int256 _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int256 _month = 80 * L / 2447;
        int256 _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        datetime = string(
            abi.encodePacked(
                _monthToString(uint256(_month)), "-", toString(uint256(_day)), "-", toString(uint256(_year))
            )
        );
    }
}

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/master/src/tokens/ERC20.sol)
abstract contract LockeERC20 is SharedState, ILockeERC20 {

    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public override name;

    string public override symbol;

    uint8 public immutable override decimals;

    uint32 private immutable erc20_endStream;

    /*///////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;

    mapping(address => mapping(address => uint256)) public override allowance;

    /*///////////////////////////////////////////////////////////////
                           EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant override PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public override nonces;

    /*///////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address depositToken, uint256 streamId, uint32 _endDepositLock, uint32 _endStream, bool isIndefinite)
        SharedState(depositToken, _endDepositLock)
    {
        erc20_endStream = _endStream;

        if (!isIndefinite) {
            // locke + depositTokenName + streamId = lockeUSD Coin-1
            string memory datetime = DateTime.daysToDate(_endDepositLock / 1 days);
            name = string(
                abi.encodePacked("locke", ERC20(depositToken).name(), " ", DateTime.toString(streamId), ": ", datetime)
            );
            // locke + Symbol + streamId = lockeUSDC1
            // TODO: we could have start_time+stream_duration+depositlocktime as maturity-date
            // i.e. lockeETH8-AUG-14-2022

            symbol = string(
                abi.encodePacked("locke", ERC20(depositToken).symbol(), DateTime.toString(streamId), "-", datetime)
            );
        }

        decimals = 18;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*///////////////////////////////////////////////////////////////
                              ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    modifier transferabilityDelay() {
        // ensure the time is after end stream
        if (block.timestamp <= erc20_endStream) {
            revert NotTransferableYet();
        }
        _;
    }

    function transferStartTime() external view override returns (uint32) {
        return erc20_endStream;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) external override transferabilityDelay returns (bool) {
        balanceOf[msg.sender] -= amount;

        // This is safe because the sum of all user
        // balances can't exceed type(uint256).max!
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        transferabilityDelay
        returns (bool)
    {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= amount;
        }

        balanceOf[from] -= amount;

        // This is safe because the sum of all user
        // balances can't exceed type(uint256).max!
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }

    /*///////////////////////////////////////////////////////////////
                              EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // This is safe because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    hex"1901",
                    DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
                )
            );

            address recoveredAddress = ecrecover(digest, v, r, s);
            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_PERMIT_SIGNATURE");

            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual override returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /*///////////////////////////////////////////////////////////////
                       INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        // This is safe because the sum of all user
        // balances can't exceed type(uint256).max!
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        // This is safe because a user won't ever
        // have a balance larger than totalSupply!
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }
}
