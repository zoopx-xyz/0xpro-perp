// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICollateralManager {
    struct AssetConfig {
        bool enabled;
        uint16 ltvBps;
        address oracle; // e.g., OracleRouter for MVP
        uint8 decimals;
    }

    function setAssetConfig(address asset, bool enabled, uint16 ltvBps, address oracle, uint8 decimals) external;

    function assetValueInZUSD(address asset, uint256 amount) external view returns (uint256 valueZ18);

    function collateralValueInZUSD(address asset, uint256 amount) external view returns (uint256 collatZ18);

    function config(address asset) external view returns (bool enabled, uint16 ltvBps, address oracle, uint8 decimals);
}
