// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBridgeableVault {
    function mintCreditFromBridge(address user, address asset, uint256 amount, bytes32 depositId) external;
    function burnCreditForBridge(address user, address asset, uint256 amount, bytes32 withdrawalId) external;
}
