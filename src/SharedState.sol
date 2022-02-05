pragma solidity 0.8.11;

import "./interfaces/IStream.sol";
import "./interfaces/IReimbursementToken.sol";

abstract contract SharedState is IReimbursementToken {
    uint32 private immutable endDepositLock;

    address private immutable depositToken;

    constructor(address _depositToken, uint32 _edl) {
    	depositToken = _depositToken;
    	endDepositLock = _edl;
    }

    function underlying() external override view returns (address) {
    	return depositToken;
    }

    function maturity() external override view returns (uint256) {
    	return endDepositLock;
    }
}