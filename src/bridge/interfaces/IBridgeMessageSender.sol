// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBridgeMessageSender {
    function sendDeposit(address user, address asset, uint256 amount, bytes32 depositId, bytes32 dstChain) external;
    function sendWithdrawal(address user, address asset, uint256 amount, bytes32 withdrawalId, bytes32 dstChain) external;
}
