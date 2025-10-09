// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";
import {SignedPriceOracle} from "./SignedPriceOracle.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title OracleRouter
/// @notice Simple router that queries a configured adapter per asset
contract OracleRouter is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IOracleRouter {
    struct Adapter {
        address oracle;
    }

    mapping(address => Adapter) public adapters; // asset => adapter

    event AdapterRegistered(address indexed asset, address indexed oracle);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function registerAdapter(address asset, address oracle) external onlyRole(Constants.DEFAULT_ADMIN) {
        adapters[asset] = Adapter(oracle);
        emit AdapterRegistered(asset, oracle);
    }

    function getPriceInZUSD(address asset) external view override returns (uint256 priceX1e18, bool isStale) {
        address o = adapters[asset].oracle;
        require(o != address(0), "no adapter");
        (uint256 px, uint64 ts, bool stale) = SignedPriceOracle(o).getPrice(asset);
        return (px, stale);
    }

    function getPriceAndStale(address asset) external view returns (uint256 priceX1e18, bool isStale) {
        address o = adapters[asset].oracle;
        require(o != address(0), "no adapter");
        (uint256 px, uint64 ts, bool stale) = SignedPriceOracle(o).getPrice(asset);
        return (px, stale);
    }

    uint256[50] private __gap;
}
