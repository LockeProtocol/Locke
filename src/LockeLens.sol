// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./interfaces/IStream.sol";

contract LockeLens {
    /**
     * @dev Gets the current deposit tokens for a user that haven't been streamed over
     *
     */
    function currDepositTokensNotYetStreamed(IStream stream, address who) external view returns (uint256) {
        unchecked {
            uint32 timestamp = uint32(block.timestamp);
            (, uint32 endStream,,) = stream.streamParams();
            if (block.timestamp >= endStream) {
                return 0;
            }

            (,,, uint112 tokens, uint32 lastUpdate,) = stream.tokenStreamForAccount(address(who));

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

    function lastApplicableTime(IStream stream) public view returns (uint32) {
        (uint32 startTime, uint32 endStream,,) = stream.streamParams();
        if (block.timestamp <= endStream) {
            if (block.timestamp <= startTime) {
                return startTime;
            } else {
                return uint32(block.timestamp);
            }
        } else {
            return endStream;
        }
    }

    /**
     * @dev Gets a stream's remaining reward tokens that haven't been allocated
     *
     */
    function rewardsRemainingToAllocate(IStream stream) external view returns (uint256) {
        uint32 timestamp = uint32(block.timestamp);
        (uint32 startTime, uint32 endStream,,) = stream.streamParams();
        uint32 streamDuration = endStream - startTime;

        (uint112 rewardTokenAmount,) = stream.tokenAmounts();

        if (timestamp > endStream) {
            return 0;
        }
        if (timestamp <= startTime) {
            return rewardTokenAmount;
        }

        return uint256(endStream - timestamp) * rewardTokenAmount / streamDuration;
    }

    /**
     * @dev Gets the current unstreamed deposit tokens for a stream
     *
     */
    function currUnstreamed(IStream stream) external view returns (uint256) {
        uint32 timestamp = uint32(block.timestamp);
        (uint32 startTime, uint32 endStream,,) = stream.streamParams();

        if (timestamp >= endStream) {
            return 0;
        }

        uint256 unstreamed = stream.unstreamed();
        if (timestamp < startTime) {
            return unstreamed;
        }

        uint32 lastUpdate = stream.lastUpdate();
        uint32 tdelta = timestamp - lastUpdate;
        return unstreamed - (uint256(tdelta) * unstreamed / (endStream - lastUpdate));
    }
}
