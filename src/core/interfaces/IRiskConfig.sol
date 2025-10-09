// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRiskConfig {
    struct MarketRisk {
        uint16 imrBps;
        uint16 mmrBps;
        uint16 liqPenaltyBps;
        uint16 makerFeeBps;
        uint16 takerFeeBps;
        uint8 maxLev;
    }

    function risks(bytes32 marketId) external view returns (uint16, uint16, uint16, uint16, uint16, uint8);
    function getMarketRisk(bytes32 marketId) external view returns (MarketRisk memory);
    function getIMRBps(bytes32 marketId) external view returns (uint16);
    function getMMRBps(bytes32 marketId) external view returns (uint16);
    function getLiqPenaltyBps(bytes32 marketId) external view returns (uint16);

    function requiredInitialMarginZ(
        bytes32 marketId,
        address baseAsset,
        uint256 sizeRaw,
        uint8 assetDecimals,
        uint256 priceX1e18
    ) external view returns (uint256);
}
