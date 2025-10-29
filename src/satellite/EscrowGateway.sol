// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title EscrowGateway (Satellite)
/// @notice Custodies user tokens on a satellite chain and coordinates cross-chain crediting on the base chain
contract EscrowGateway is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // Map of supported assets
    mapping(address => bool) public isSupportedAsset;
    address public messageSenderAdapter; // Optional outbound message sender

    event SupportedAssetSet(address indexed asset, bool enabled);
    event DepositEscrowed(
        address indexed user, address indexed asset, uint256 amount, bytes32 indexed depositId, bytes32 dstChain
    );
    event WithdrawalReleased(address indexed user, address indexed asset, uint256 amount, bytes32 indexed withdrawalId);
    event MessageSenderAdapterSet(address indexed adapter);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.MESSAGE_SENDER_ROLE, admin);
        _grantRole(Constants.MESSAGE_RECEIVER_ROLE, admin);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setSupportedAsset(address asset, bool enabled) external onlyRole(Constants.DEFAULT_ADMIN) {
        isSupportedAsset[asset] = enabled;
        emit SupportedAssetSet(asset, enabled);
    }

    function setMessageSenderAdapter(address adapter_) external onlyRole(Constants.DEFAULT_ADMIN) {
        messageSenderAdapter = adapter_;
        emit MessageSenderAdapterSet(adapter_);
    }

    /// @notice User deposits tokens on satellite; gateway locks tokens and emits a deposit intent
    function deposit(address asset, uint256 amount, bytes32 dstChain) external nonReentrant whenNotPaused {
        require(isSupportedAsset[asset], "asset not supported");
        require(amount > 0, "amount=0");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        bytes32 depositId = keccak256(abi.encodePacked(msg.sender, asset, amount, block.number, address(this)));
        emit DepositEscrowed(msg.sender, asset, amount, depositId, dstChain);
        // If configured, forward message to outbound sender adapter
        if (messageSenderAdapter != address(0)) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool ok,) = messageSenderAdapter.call(
                abi.encodeWithSignature(
                    "sendDeposit(address,address,uint256,bytes32,bytes32)",
                    msg.sender,
                    asset,
                    amount,
                    depositId,
                    dstChain
                )
            );
            require(ok, "sender adapter call failed");
        }
    }

    /// @notice Release escrowed tokens after verified burn on base chain
    function completeWithdrawal(address user, address asset, uint256 amount, bytes32 withdrawalId)
        external
        onlyRole(Constants.MESSAGE_RECEIVER_ROLE)
        nonReentrant
        whenNotPaused
    {
        IERC20(asset).safeTransfer(user, amount);
        emit WithdrawalReleased(user, asset, amount, withdrawalId);
    }
}
