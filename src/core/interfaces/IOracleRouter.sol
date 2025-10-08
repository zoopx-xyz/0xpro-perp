// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IOracleRouter {
    function getPriceInZUSD(address asset) external view returns (uint256 priceX1e18, bool isStale);
    function getPriceAndStale(address asset) external view returns (uint256 priceX1e18, bool isStale);
}
