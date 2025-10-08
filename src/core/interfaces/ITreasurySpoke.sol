// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasurySpoke {
    function balanceOf(address token) external view returns (uint256);
    function forwardFeesToSplitter(uint256 amount, address splitter) external;
    function receivePenalty(uint256 amount) external;
}
