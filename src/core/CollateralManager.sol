// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title CollateralManager
/// @notice Stores per-asset configs, LTVs and valuation helpers
contract CollateralManager is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    ICollateralManager
{
    using Constants for uint256;

    mapping(address => AssetConfig) public config;
    address[] private _assets;
    mapping(address => bool) private _isAssetKnown;

    IOracleRouter public oracleRouter;

    event AssetConfigSet(address indexed asset, bool enabled, uint16 ltvBps, address oracle, uint8 decimals);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address _oracleRouter) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.RISK_ADMIN, admin);
        oracleRouter = IOracleRouter(_oracleRouter);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setAssetConfig(address asset, bool enabled, uint16 ltvBps, address oracle, uint8 decimals_)
        external
        override
        onlyRole(Constants.RISK_ADMIN)
    {
        if (!_isAssetKnown[asset]) {
            _isAssetKnown[asset] = true;
            _assets.push(asset);
        }
        config[asset] = AssetConfig({enabled: enabled, ltvBps: ltvBps, oracle: oracle, decimals: decimals_});
        emit AssetConfigSet(asset, enabled, ltvBps, oracle, decimals_);
    }

    function assetValueInZUSD(address asset, uint256 amount) public view override returns (uint256 valueZ18) {
        AssetConfig memory c = config[asset];
        require(c.enabled, "asset disabled");
        (uint256 px, bool stale) = IOracleRouter(c.oracle).getPriceInZUSD(asset);
        require(!stale, "stale price");
        // value = amount * price / 10**decimals
        valueZ18 = amount * px / (10 ** c.decimals);
    }

    function collateralValueInZUSD(address asset, uint256 amount) external view override returns (uint256 collatZ18) {
        AssetConfig memory c = config[asset];
        uint256 gross = assetValueInZUSD(asset, amount);
        collatZ18 = gross * uint256(c.ltvBps) / 10_000;
    }

    function getAssets() external view returns (address[] memory) {
        return _assets;
    }

    uint256[50] private __gap;
}
