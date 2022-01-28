// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Locke.sol";

contract LockeLens {

	function depositTokensNotYetStreamed(Stream stream, address who) public view returns (uint256) {
		(
            uint256 lastCumulativeRewardPerToken,
            uint256 virtualBalance,
            uint112 rewards,
            uint112 tokens,
            uint32 lastUpdate,
            bool merkleAccess
        ) = stream.tokenStreamForAccount(address(who));

        
	}
}