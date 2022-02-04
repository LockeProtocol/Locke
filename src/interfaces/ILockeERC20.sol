// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface ILockeERC20 {
    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function name() external view returns (string memory name);
    function symbol() external view returns (string memory symbol);
    function decimals() external view returns (uint8 decimals);
    function transferStartTime() external view returns (uint32 transferStartTime);
    function totalSupply() external view returns (uint256 totalSupply);
    function balanceOf(address who) external view returns (uint256 balanceOf);
    function allowance(address owner, address spender) external view returns (uint256 allowance);
    function PERMIT_TYPEHASH() external view returns (bytes32 PERMIT_TYPEHASH);
    function nonces(address who) external view returns (uint256 nonce);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}