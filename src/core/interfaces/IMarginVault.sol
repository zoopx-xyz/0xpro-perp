// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMarginVault {
    function deposit(address asset, uint256 amount, bool isolated, bytes32 marketId) external;
    function withdraw(address asset, uint256 amount, bool isolated, bytes32 marketId) external;

    function reserve(address user, address asset, uint256 amount, bool isolated, bytes32 marketId) external;
    function release(address user, address asset, uint256 amount, bool isolated, bytes32 marketId) external;

    function accountEquityZUSD(address user) external view returns (int256);

    /// @notice Returns cross balance (raw token units) for a user and asset (MVP helper for engine penalty logic)
    function getCrossBalance(address user, address asset) external view returns (uint128);

    /// @notice Penalize a user's cross balance and transfer asset to destination without affecting reserved margin.
    /// @dev Used for liquidation penalties; MUST be restricted to ENGINE role in implementation.
    function penalize(address user, address asset, uint256 amount, address to) external;
}
