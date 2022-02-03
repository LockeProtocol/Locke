// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Locke.sol";

contract LockeLens {
    /**
     * @dev Gets the current deposit tokens for a user that haven't been streamed over 
     **/
	function currDepositTokensNotYetStreamed(Stream stream, address who) public view returns (uint256) {
        unchecked {
            uint32 timestamp = uint32(block.timestamp);
            (uint32 startTime, uint32 streamDuration, ,) = stream.streamParams();
            uint32 endStream = startTime + streamDuration;

            if (block.timestamp >= endStream) return 0;


            (
                uint256 lastCumulativeRewardPerToken,
                uint256 virtualBalance,
                uint112 rewards,
                uint112 tokens,
                uint32 lastUpdate,
                bool merkleAccess
            ) = stream.tokenStreamForAccount(address(who));

            if (timestamp < lastUpdate) {
                return tokens;
            }

            uint32 acctTimeDelta = timestamp - lastUpdate;

            if (acctTimeDelta > 0) {
                uint256 streamAmt = uint256(acctTimeDelta) * tokens / (endStream - lastUpdate);
                return tokens - uint112(streamAmt);
            } else {
                return tokens;
            }
        }
	}

    /**
     * @dev Gets a stream's remaining reward tokens that haven't been allocated
     **/
    function rewardsRemainingToAllocate(Stream stream) public view returns (uint256) {
        uint32 timestamp = uint32(block.timestamp);
        (uint32 startTime, uint32 streamDuration, ,) = stream.streamParams();
        uint32 endStream = startTime + streamDuration;

        (
            uint112 rewardTokenAmount,
            uint112 depositTokenAmount,
            uint112 rewardTokenFeeAmount,
            uint112 depositTokenFlashloanFeeAmount
        ) = stream.tokenAmounts();

        if (endStream < timestamp) return 0;
        
        return uint256(endStream - timestamp) * rewardTokenAmount / streamDuration;
    }

    /**
     * @dev Gets the current unstreamed deposit tokens for a stream
     **/
    function currUnstreamed(Stream stream) public view returns (uint256) {
        uint32 timestamp = uint32(block.timestamp);
        (uint32 startTime, uint32 streamDuration, ,) = stream.streamParams();
        uint32 endStream = startTime + streamDuration;

        if (timestamp >= endStream) return 0;
        
        uint32 lastUpdate = stream.lastUpdate();
        uint32 tdelta = timestamp - lastUpdate;
        uint256 unstreamed = stream.unstreamed();
        return unstreamed - (uint256(tdelta) * unstreamed / (endStream - lastUpdate));
    }
}