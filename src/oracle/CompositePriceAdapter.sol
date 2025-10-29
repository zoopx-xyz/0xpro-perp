// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IPriceAdapter} from "../core/interfaces/IPriceAdapter.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title CompositePriceAdapter
/// @notice Tries primary first (e.g., Stork). If stale or deviates beyond bounds, falls back to secondary (e.g., SignedPriceOracle).
contract CompositePriceAdapter is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IPriceAdapter
{
    IPriceAdapter public primary;
    IPriceAdapter public secondary; // optional

    struct Policy {
        bool fallbackOnStale; // if primary stale, try secondary
        uint16 maxDeviationBps; // if >0, require |p - s|/s <= maxDeviationBps; if s is stale, skip check
    }

    mapping(address => Policy) public policyOf; // per-asset policy

    event PrimarySet(address indexed adapter);
    event SecondarySet(address indexed adapter);
    event PolicySet(address indexed asset, bool fallbackOnStale, uint16 maxDeviationBps);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address primary_, address secondary_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        primary = IPriceAdapter(primary_);
        secondary = IPriceAdapter(secondary_);
        emit PrimarySet(primary_);
        emit SecondarySet(secondary_);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setPrimary(address a) external onlyRole(Constants.DEFAULT_ADMIN) {
        primary = IPriceAdapter(a);
        emit PrimarySet(a);
    }

    function setSecondary(address a) external onlyRole(Constants.DEFAULT_ADMIN) {
        secondary = IPriceAdapter(a);
        emit SecondarySet(a);
    }

    function setPolicy(address asset, bool fallbackOnStale, uint16 maxDeviationBps)
        external
        onlyRole(Constants.DEFAULT_ADMIN)
    {
        policyOf[asset] = Policy(fallbackOnStale, maxDeviationBps);
        emit PolicySet(asset, fallbackOnStale, maxDeviationBps);
    }

    function getPrice(address asset) external view returns (uint256 px18, uint64 ts, bool stale) {
        (uint256 pPx, uint64 pTs, bool pStale) = primary.getPrice(asset);
        Policy memory pol = policyOf[asset];

        if (!pStale) {
            if (pol.maxDeviationBps == 0 || address(secondary) == address(0)) {
                return (pPx, pTs, false);
            }
            (uint256 sPx,, bool sStale) = secondary.getPrice(asset);
            if (!sStale && sPx > 0) {
                uint256 diff = pPx > sPx ? pPx - sPx : sPx - pPx;
                if (diff * 10_000 <= sPx * pol.maxDeviationBps) {
                    return (pPx, pTs, false);
                }
            }
            // deviation too high or secondary unusable: fall through to fallback if allowed
        }

        if (pol.fallbackOnStale && address(secondary) != address(0)) {
            (uint256 sPx, uint64 sTs, bool sStale) = secondary.getPrice(asset);
            return (sPx, sTs, sStale);
        }
        // Either primary stale and no fallback, or deviation too high and no fallback policy set
        return (pPx, pTs, pStale || (pol.maxDeviationBps > 0));
    }
}
