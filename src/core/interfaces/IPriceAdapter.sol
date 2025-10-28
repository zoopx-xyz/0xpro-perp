// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IPriceAdapter {
    function getPrice(address asset) external view returns (uint256 priceX1e18, uint64 ts, bool isStale);
}
