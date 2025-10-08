// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITreasurySpoke {
    function balanceOf(address token) external view returns (uint256);
}
