// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IReimbursementToken.sol";
import "./ILockeERC20.sol";


interface IStream is ILockeERC20 {
	    // ======= Events ========
    event StreamFunded(uint256 amount);
    event Staked(address indexed who, uint256 amount);
    event Withdrawn(address indexed who, uint256 amount);
    event StreamIncentivized(address indexed token, uint256 amount);
    event StreamIncentiveClaimed(address indexed token, uint256 amount);
    event TokensClaimed(address indexed who, uint256 amount);
    event DepositTokensReclaimed(address indexed who, uint256 amount);
    event FeesClaimed(address indexed token, address indexed who, uint256 amount);
    event RecoveredTokens(address indexed token, address indexed recipient, uint256 amount);
    event RewardsClaimed(address indexed who, uint256 amount);
    event Flashloaned(address indexed token, address indexed who, uint256 amount, uint256 fee);

    // =======   Errors  ========
    error NotStream();
    error ZeroAmount();
    error BalanceError();
    error Reentrant();
    error NotBeforeStream();
    error BadERC20Interaction();
    error NotCreator();
    error StreamOngoing();
    error StreamTypeError();
    error LockOngoing();

    // =======   View Functions  ========
	function tokenStreamForAccount(address who) external view returns (
		uint256 lastCumulativeRewardPerToken,
		uint256 virtualBalance,
		uint112 rewards,
		uint112 tokens,
		uint32 lastUpdate,
		bool merkleAccess
	);
	function streamParams() external view returns (
		uint32 startTime,
		uint32 endStream,
		uint32 endDepositLock,
		uint32 endRewardLock
	);
	function tokenAmounts() external view returns (
		uint112 rewardTokenAmount,
		uint112 depositTokenAmount,
		uint112 rewardTokenFeeAmount,
		uint112 depositTokenFlashloanFeeAmount
	);
	function lastUpdate() external view returns (uint32 _lastUpdate);
	function isIndefinite() external view returns (bool _isIndefinite);
	function unstreamed() external view returns (uint112 _unstreamed);
	function rewardPerToken() external view returns (uint256 _rewardPerToken);
	function depositToken() external view returns (address);
	function rewardToken() external view returns (address _rewardToken);
	function streamCreator() external view returns (address _streamCreator);
	function streamId() external view returns (uint64 _streamId);
	function feeParams() external view returns (uint16 _feePercent, bool _feeEnabled);
	function incentives(address token) external view returns (uint112 amount, bool flag);
	function getEarned(address who) external view returns (uint256 rewardEarned);
	function totalVirtualBalance() external view returns (uint256);
	function redeemedDepositTokens() external view returns (uint112);

	// ======= State modifying Functions  ========
	function arbitraryCall(address who, bytes calldata data) external;
	function createIncentive(address token, uint112 amount) external;
	function stake(uint112 amount) external;
	function withdraw(uint112 amount) external;
	function fundStream(uint112 amount) external;
	function creatorClaim(address destination) external;
	function recoverTokens(address token, address destination) external;
	function exit() external;
	function claimReward() external;
	function claimDepositTokens(uint112 amount) external;
	
	function claimFees(address destination) external;
	function flashloan(address token, address to, uint112 amount, bytes calldata data) external;
	function claimIncentive(address token) external;
}