// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title AssetMapper
/// @notice Canonical mapping between satellite-chain asset addresses and base-chain assets per chain domain
contract AssetMapper is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    // chainDomain => satelliteAsset => baseAsset
    mapping(bytes32 => mapping(address => address)) public satToBase;
    // chainDomain => baseAsset => satelliteAsset
    mapping(bytes32 => mapping(address => address)) public baseToSat;

    event MappingSet(bytes32 indexed chain, address indexed satelliteAsset, address indexed baseAsset);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address admin) external initializer {
        __AccessControl_init(); __UUPSUpgradeable_init(); __ReentrancyGuard_init(); __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setMapping(bytes32 chainDomain, address satelliteAsset, address baseAsset) external onlyRole(Constants.DEFAULT_ADMIN) {
        require(satelliteAsset != address(0) && baseAsset != address(0), "zero addr");
        satToBase[chainDomain][satelliteAsset] = baseAsset;
        baseToSat[chainDomain][baseAsset] = satelliteAsset;
        emit MappingSet(chainDomain, satelliteAsset, baseAsset);
    }

    function getBaseAsset(bytes32 chainDomain, address satelliteAsset) external view returns (address) {
        return satToBase[chainDomain][satelliteAsset];
    }

    function getSatelliteAsset(bytes32 chainDomain, address baseAsset) external view returns (address) {
        return baseToSat[chainDomain][baseAsset];
    }
}
