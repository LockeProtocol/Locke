// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC20.sol";
import "./interfaces/ILockeERC20.sol";
import "./SharedState.sol";

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/master/src/tokens/ERC20.sol)
abstract contract LockeERC20 is SharedState, ILockeERC20 {
    error NotTransferableYet();
    /*///////////////////////////////////////////////////////////////
                             METADATA STORAGE
    //////////////////////////////////////////////////////////////*/

    string public override name;

    string public override symbol;

    uint8 public override immutable decimals;

    uint32 private immutable endDepositLock;
    uint32 private immutable endStream;

    /*///////////////////////////////////////////////////////////////
                              ERC20 STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;

    mapping(address => mapping(address => uint256)) public override allowance;

    /*///////////////////////////////////////////////////////////////
                           EIP-2612 STORAGE
    //////////////////////////////////////////////////////////////*/

    bytes32 public override constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 internal immutable INITIAL_CHAIN_ID;

    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    mapping(address => uint256) public override nonces;

    /*///////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address depositToken,
        uint256 streamId,
        uint32 _endDepositLock,
        uint32 _endStream,
        bool isIndefinite
    )
        SharedState(depositToken, _endDepositLock, _endStream)
    {
        endDepositLock = _endDepositLock;
        endStream = _endStream;

        if (!isIndefinite) {
            // locke + depositTokenName + streamId = lockeUSD Coin-1
            (uint256 year, uint256 month, uint256 day) = _daysToDate(endDepositLock / 86400);
            name = string(abi.encodePacked(
                "locke",
                ERC20(depositToken).name(),
                ": ",
                toString(streamId),
                " ,",
                _monthToString(month),
                "-",
                toString(day),
                "-",
                toString(year)
            ));
            // locke + Symbol + streamId = lockeUSDC1
            // TODO: we could have start_time+stream_duration+depositlocktime as maturity-date
            // i.e. lockeETH8-AUG-14-2022

            symbol = string(abi.encodePacked(
                "locke",
                ERC20(depositToken).symbol(),
                toString(streamId),
                "-",
                _monthToString(month),
                "-",
                toString(day),
                "-",
                toString(year)
            ));
        }

        decimals = 18;

        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    function _monthToString(uint256 month) internal pure returns (string memory s) {
        assembly {
            mstore(s, 0x03)
            switch month
            case 1 { mstore(add(s, 0x20), "JAN") }
            case 2 { mstore(add(s, 0x20), "FEB") }
            case 3 { mstore(add(s, 0x20), "MAR") }
            case 4 { mstore(add(s, 0x20), "APR") }
            case 5 { mstore(add(s, 0x20), "MAY") }
            case 6 { mstore(add(s, 0x20), "JUN") }
            case 7 { mstore(add(s, 0x20), "JUL") }
            case 8 { mstore(add(s, 0x20), "AUG") }
            case 9 { mstore(add(s, 0x20), "SEP") }
            case 10 { mstore(add(s, 0x20), "OCT") }
            case 11 { mstore(add(s, 0x20), "NOV") }
            case 12 { mstore(add(s, 0x20), "DEC") }
        }
    }

    function _daysToDate(uint _days) internal pure returns (uint year, uint month, uint day) {
        int __days = int(_days);

        int L = __days + 68569 + 2440588;
        int N = 4 * L / 146097;
        L = L - (146097 * N + 3) / 4;
        int _year = 4000 * (L + 1) / 1461001;
        L = L - 1461 * _year / 4 + 31;
        int _month = 80 * L / 2447;
        int _day = L - 2447 * _month / 80;
        L = _month / 11;
        _month = _month + 2 - 12 * L;
        _year = 100 * (N - 49) + _year + L;

        year = uint(_year);
        month = uint(_month);
        day = uint(_day);
    }

    /*///////////////////////////////////////////////////////////////
                              ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    modifier transferabilityDelay {
        // ensure the time is after start time
        if (block.timestamp < endStream) revert NotTransferableYet();
        _;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) transferabilityDelay external override returns (bool) {
        balanceOf[msg.sender] -= amount;

        // This is safe because the sum of all user
        // balances can't exceed type(uint256).max!
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) transferabilityDelay external override returns (bool) {
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

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // This is safe because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
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
        return
            keccak256(
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


    // Helpers
    function toString(uint _i)
        internal
        pure
        returns (string memory) 
    {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
