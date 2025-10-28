// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBridgeAdapter {
    event BridgeCreditReceived(address indexed user, address indexed asset, uint256 amount, bytes32 indexed depositId, bytes32 srcChain);
    event BridgeWithdrawalInitiated(address indexed user, address indexed asset, uint256 amount, bytes32 indexed withdrawalId, bytes32 dstChain);

    function creditFromMessage(address user, address asset, uint256 amount, bytes32 depositId, bytes32 srcChain) external;
    function initiateWithdrawal(address asset, uint256 amount, bytes32 dstChain) external returns (bytes32 withdrawalId);
}
