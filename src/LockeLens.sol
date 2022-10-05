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

            (,, uint176 tokens, uint32 lastUpdate,,) = stream.tokenStreamForAccount(address(who));

            if (timestamp < lastUpdate) {
                return tokens;
            }

            uint32 acctTimeDelta = timestamp - lastUpdate;

            if (acctTimeDelta > 0) {
                // some time has passed since this user last interacted
                // update ts not yet streamed
                // downcast is safe as guaranteed to be a % of uint112
                if (tokens > 0) {
                    // Safety:
                    //  1. endStream guaranteed to be greater than the current timestamp, see first line in this modifier
                    //  2. (endStream - timestamp) * ts.tokens: (endStream - timestamp) is uint32, ts.tokens is uint112, cannot overflow uint256
                    //  3. endStream - ts.lastUpdate: We are guaranteed to not update ts.lastUpdate after endStream
                    return uint176(uint256(endStream - timestamp) * tokens / (endStream - lastUpdate)) / 10 ** 18;
                } else {
                    return 0;
                }
            } else {
                return tokens / 10 ** 18;
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
