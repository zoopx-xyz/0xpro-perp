// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Constants} from "../../lib/Constants.sol";
import {MathUtils} from "../../lib/MathUtils.sol";

contract RiskConfig is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    struct MarketRisk { uint16 imrBps; uint16 mmrBps; uint16 liqPenaltyBps; uint16 makerFeeBps; uint16 takerFeeBps; uint8 maxLev; }
    mapping(bytes32 => MarketRisk) public risks;

    event MarketRiskSet(bytes32 indexed marketId, MarketRisk risk);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.RISK_ADMIN, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setMarketRisk(bytes32 marketId, MarketRisk calldata r) external onlyRole(Constants.RISK_ADMIN) {
        risks[marketId] = r;
        emit MarketRiskSet(marketId, r);
    }

    function getMarketRisk(bytes32 marketId) external view returns (MarketRisk memory) {
        return risks[marketId];
    }

    function getIMRBps(bytes32 marketId) external view returns (uint16) {
        return risks[marketId].imrBps;
    }

    function getMMRBps(bytes32 marketId) external view returns (uint16) {
        return risks[marketId].mmrBps;
    }

    function getLiqPenaltyBps(bytes32 marketId) external view returns (uint16) {
        return risks[marketId].liqPenaltyBps;
    }

    function requiredInitialMarginZ(bytes32 marketId, address /*baseAsset*/, uint256 sizeRaw, uint8 assetDecimals, uint256 priceX1e18) external view returns (uint256) {
        uint256 notionalZ = MathUtils.notionalZFromSize(sizeRaw, assetDecimals, priceX1e18);
        uint16 imr = risks[marketId].imrBps;
        return (notionalZ * imr) / 10_000;
    }

    uint256[50] private __gap;
}
