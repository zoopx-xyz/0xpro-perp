// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Constants} from "../../lib/Constants.sol";

contract MarketFactory is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    struct MarketParams {
        address base;
        uint8 baseDecimals;
        uint8 quoteDecimals;
    }

    mapping(bytes32 => MarketParams) public markets;

    event MarketCreated(bytes32 indexed marketId, address base, uint8 baseDecimals, uint8 quoteDecimals);

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

    function createMarket(
        bytes32 marketId,
        address base,
        uint8 baseDecimals,
        uint8 quoteDecimals,
        MarketParams calldata params
    ) external onlyRole(Constants.DEFAULT_ADMIN) {
        markets[marketId] = params;
        emit MarketCreated(marketId, base, baseDecimals, quoteDecimals);
    }

    uint256[50] private __gap;
}
