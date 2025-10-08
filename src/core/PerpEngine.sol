// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IMarginVault} from "./interfaces/IMarginVault.sol";
import {IPerpEngine} from "./interfaces/IPerpEngine.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title PerpEngine (MVP)
contract PerpEngine is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IPerpEngine {
    IMarginVault public vault;

    // idempotency
    mapping(bytes32 => bool) public seenFill;

    // simple position: account => marketId => size (signed)
    mapping(address => mapping(bytes32 => int256)) public positions;

    event OrderFilled(address indexed account, bytes32 indexed marketId, bytes32 indexed fillId, bool isBuy, uint128 size, uint128 priceZ, uint128 feeZ, int128 fundingZ, int256 positionAfter);
    event PositionUpdated(address indexed account, bytes32 marketId, int256 newSize, uint128 entryPriceZ, int256 unrealizedPnlZ);
    event Liquidation(address indexed account, bytes32 marketId, uint128 closedSize, uint128 priceZ, uint128 penaltyZ);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address admin, address _vault) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.KEEPER, admin);
        _grantRole(Constants.ENGINE_ADMIN, admin);
        vault = IMarginVault(_vault);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function recordFill(Fill calldata f) external override onlyRole(Constants.KEEPER) nonReentrant {
        require(!seenFill[f.fillId], "dup fillId");
        seenFill[f.fillId] = true;

        // Update positions: buy increases size, sell decreases
        int256 s = positions[f.account][f.marketId];
        s += f.isBuy ? int256(uint256(f.size)) : -int256(uint256(f.size));
        positions[f.account][f.marketId] = s;

        emit OrderFilled(f.account, f.marketId, f.fillId, f.isBuy, f.size, f.priceZ, f.feeZ, f.fundingZ, s);
        emit PositionUpdated(f.account, f.marketId, s, f.priceZ, 0);
    }

    function liquidate(address account, bytes32 marketId) external onlyRole(Constants.KEEPER) {
        int256 pos = positions[account][marketId];
        require(pos != 0, "no pos");
        uint128 closed = uint128(pos > 0 ? uint256(pos) : uint256(-pos));
        positions[account][marketId] = 0;
        emit Liquidation(account, marketId, closed, 0, 0);
    }

    uint256[50] private __gap;
}
