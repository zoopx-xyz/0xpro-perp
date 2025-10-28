// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IPriceAdapter} from "../core/interfaces/IPriceAdapter.sol";
import {IStork} from "./external/stork/IStork.sol";
import {StorkStructs} from "./external/stork/StorkStructs.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title StorkPriceAdapter
/// @notice IPriceAdapter implementation backed by Stork feeds
contract StorkPriceAdapter is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IPriceAdapter {
    IStork public stork;
    // asset => feedId
    mapping(address => bytes32) public feedIdOf;
    // feedId => decimals for normalization to 1e18
    mapping(bytes32 => uint8) public feedDecimals;

    event StorkSet(address indexed stork);
    event FeedSet(address indexed asset, bytes32 indexed feedId, uint8 decimals);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address stork_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        stork = IStork(stork_);
        emit StorkSet(stork_);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setStork(address stork_) external onlyRole(Constants.DEFAULT_ADMIN) {
        stork = IStork(stork_);
        emit StorkSet(stork_);
    }

    function setFeed(address asset, bytes32 feedId, uint8 decimals_) external onlyRole(Constants.DEFAULT_ADMIN) {
        require(asset != address(0) && feedId != bytes32(0), "bad args");
        feedIdOf[asset] = feedId;
        feedDecimals[feedId] = decimals_;
        emit FeedSet(asset, feedId, decimals_);
    }

    /// @inheritdoc IPriceAdapter
    function getPrice(address asset) external view returns (uint256 priceX1e18, uint64 ts, bool isStale) {
        bytes32 fid = feedIdOf[asset];
        require(fid != bytes32(0), "no feed");
        // Stork enforces staleness in getTemporalNumericValueV1 by reverting on stale
        // We'll treat any revert as stale and return isStale=true with price=0
        try stork.getTemporalNumericValueV1(fid) returns (StorkStructs.TemporalNumericValue memory v) {
            ts = v.timestamp;
            // value may be signed; require non-negative price
            require(v.value >= 0, "neg price");
            uint256 raw = uint256(v.value);
            uint8 dec = feedDecimals[fid];
            if (dec < 18) priceX1e18 = raw * (10 ** (18 - dec));
            else if (dec > 18) priceX1e18 = raw / (10 ** (dec - 18));
            else priceX1e18 = raw;
            isStale = false;
        } catch {
            // Stork NotFound or StaleValue -> mark stale
            return (0, 0, true);
        }
    }
}
