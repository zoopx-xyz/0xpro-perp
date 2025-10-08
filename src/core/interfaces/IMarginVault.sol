// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IMarginVault {
    function deposit(address asset, uint256 amount, bool isolated, bytes32 marketId) external;
    function withdraw(address asset, uint256 amount, bool isolated, bytes32 marketId) external;

    function reserve(address user, address asset, uint256 amount, bool isolated, bytes32 marketId) external;
    function release(address user, address asset, uint256 amount, bool isolated, bytes32 marketId) external;

    function accountEquityZUSD(address user) external view returns (int256);
}
