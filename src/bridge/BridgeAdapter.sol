// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IBridgeAdapter} from "./interfaces/IBridgeAdapter.sol";
import {IBridgeableVault} from "../core/interfaces/IBridgeableVault.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title BridgeAdapter
/// @notice Base-chain adapter that mints/burns margin credit upon verified cross-chain messages
contract BridgeAdapter is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    IBridgeAdapter
{
    IBridgeableVault public vault;
    address public messageSenderAdapter; // Optional outbound message sender
    // Rate limiting config per asset

    struct Limits {
        uint256 maxPerAssetPerWindow;
        uint256 maxPerUserPerWindow;
        uint64 windowSeconds;
        bool enabled;
    }

    mapping(address => Limits) public limits; // asset => limits
    // usage tracking (windowStart => used)
    mapping(address => mapping(uint64 => uint256)) public usedByAsset;
    mapping(address => mapping(address => mapping(uint64 => uint256))) public usedByUser; // user=>asset=>window=>used

    event VaultSet(address indexed vault);
    event MessageSenderAdapterSet(address indexed adapter);
    event LimitsSet(
        address indexed asset,
        uint256 maxPerAssetPerWindow,
        uint256 maxPerUserPerWindow,
        uint64 windowSeconds,
        bool enabled
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address _vault) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.BRIDGE_ROLE, admin);
        _grantRole(Constants.MESSAGE_RECEIVER_ROLE, admin);
        vault = IBridgeableVault(_vault);
        emit VaultSet(_vault);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setVault(address _vault) external onlyRole(Constants.DEFAULT_ADMIN) {
        vault = IBridgeableVault(_vault);
        emit VaultSet(_vault);
    }

    function setMessageSenderAdapter(address adapter_) external onlyRole(Constants.DEFAULT_ADMIN) {
        messageSenderAdapter = adapter_;
        emit MessageSenderAdapterSet(adapter_);
    }

    function setLimits(address asset, uint256 maxAsset, uint256 maxUser, uint64 windowSec, bool enabled)
        external
        onlyRole(Constants.DEFAULT_ADMIN)
    {
        limits[asset] = Limits(maxAsset, maxUser, windowSec, enabled);
        emit LimitsSet(asset, maxAsset, maxUser, windowSec, enabled);
    }

    /// @notice Called by a verified message receiver after bridge proof
    function creditFromMessage(address user, address asset, uint256 amount, bytes32 depositId, bytes32 srcChain)
        external
        override
        onlyRole(Constants.MESSAGE_RECEIVER_ROLE)
        nonReentrant
        whenNotPaused
    {
        // Rate limiting
        Limits memory lim = limits[asset];
        if (lim.enabled && amount > 0) {
            uint64 window = lim.windowSeconds == 0 ? uint64(0) : uint64(block.timestamp / lim.windowSeconds);
            if (lim.maxPerAssetPerWindow > 0) {
                uint256 ua = usedByAsset[asset][window] + amount;
                require(ua <= lim.maxPerAssetPerWindow, "asset limit");
                usedByAsset[asset][window] = ua;
            }
            if (lim.maxPerUserPerWindow > 0) {
                uint256 uu = usedByUser[user][asset][window] + amount;
                require(uu <= lim.maxPerUserPerWindow, "user limit");
                usedByUser[user][asset][window] = uu;
            }
        }
        // mint credit to user; depositId ensures off-chain idempotency
        // mint does not alter reservedZ
        vault.mintCreditFromBridge(user, asset, amount, depositId);
        emit BridgeCreditReceived(user, asset, amount, depositId, srcChain);
    }

    /// @notice User-initiated withdrawal to a destination chain; burns credit and emits intent
    function initiateWithdrawal(address asset, uint256 amount, bytes32 dstChain)
        external
        override
        nonReentrant
        whenNotPaused
        returns (bytes32 withdrawalId)
    {
        require(amount > 0, "amount=0");
        // withdrawalId can be computed as keccak(user, asset, amount, block.number)
        withdrawalId = keccak256(abi.encodePacked(msg.sender, asset, amount, block.number, address(this)));
        vault.burnCreditForBridge(msg.sender, asset, amount, withdrawalId);
        emit BridgeWithdrawalInitiated(msg.sender, asset, amount, withdrawalId, dstChain);
        // If configured, forward message to outbound sender adapter
        if (messageSenderAdapter != address(0)) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool ok,) = messageSenderAdapter.call(
                abi.encodeWithSignature(
                    "sendWithdrawal(address,address,uint256,bytes32,bytes32)",
                    msg.sender,
                    asset,
                    amount,
                    withdrawalId,
                    dstChain
                )
            );
            require(ok, "sender adapter call failed");
        }
    }
}
