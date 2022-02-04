pragma solidity 0.8.11;

import "./interfaces/IStream.sol";
import "./interfaces/IReimbursementToken.sol";

abstract contract SharedState is IReimbursementToken {
    uint32 private immutable endDepositLock;

    uint32 private immutable endStream;

    address private immutable depositToken;

    constructor(address _depositToken, uint32 _edl, uint32 _es) {
    	require(_edl > 0, "here");
    	depositToken = _depositToken;
    	endDepositLock = _edl;
    	endStream = _es;
    }

    function transferStartTime() external returns (uint32) {
    	return endStream;
    }

    function underlying() external override returns (address) {
    	return depositToken;
    }

    function maturity() external override returns (uint256) {
    	return endDepositLock;
    }
}