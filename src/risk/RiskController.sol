// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ICollateralManager} from "../core/interfaces/ICollateralManager.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title RiskController
/// @notice Optional controller to adjust LTVs under strict guardrails, calling CollateralManager.setAssetConfig
contract RiskController is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    ICollateralManager public cm;

    struct Guardrails {
        uint16 minLtvBps;   // min allowed LTV
        uint16 maxLtvBps;   // max allowed LTV
        uint16 maxStepBps;  // max change per update
        uint64 minInterval; // min seconds between updates
        uint64 lastUpdate;  // last update timestamp
    }

    mapping(address => Guardrails) public rails; // per-asset

    event GuardrailsSet(address indexed asset, uint16 minLtv, uint16 maxLtv, uint16 maxStep, uint64 minInterval);
    event LtvUpdated(address indexed asset, uint16 oldLtv, uint16 newLtv);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address collateralManager) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.RISK_ADMIN, admin);
        cm = ICollateralManager(collateralManager);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setGuardrails(address asset, uint16 minLtvBps, uint16 maxLtvBps, uint16 maxStepBps, uint64 minInterval)
        external
        onlyRole(Constants.RISK_ADMIN)
    {
        require(minLtvBps <= maxLtvBps, "min>max");
        rails[asset] = Guardrails(minLtvBps, maxLtvBps, maxStepBps, minInterval, rails[asset].lastUpdate);
        emit GuardrailsSet(asset, minLtvBps, maxLtvBps, maxStepBps, minInterval);
    }

    function updateLtv(address asset, uint16 newLtvBps) external onlyRole(Constants.RISK_ADMIN) whenNotPaused {
        Guardrails storage r = rails[asset];
        require(r.maxLtvBps != 0, "rails not set");
        (bool enabled, uint16 oldLtv, address oracle, uint8 dec) = cm.config(asset);
        require(block.timestamp >= r.lastUpdate + r.minInterval, "cooldown");
        require(newLtvBps >= r.minLtvBps && newLtvBps <= r.maxLtvBps, "bounds");
        if (r.maxStepBps > 0) {
            uint256 diff = newLtvBps > oldLtv ? newLtvBps - oldLtv : oldLtv - newLtvBps;
            require(diff <= r.maxStepBps, "step too large");
        }
        cm.setAssetConfig(asset, enabled, newLtvBps, oracle, dec);
        r.lastUpdate = uint64(block.timestamp);
        emit LtvUpdated(asset, oldLtv, newLtvBps);
    }
}
