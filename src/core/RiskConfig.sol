// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Constants} from "../../lib/Constants.sol";

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

    uint256[50] private __gap;
}
