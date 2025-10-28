// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IBridgeMessageSender} from "../interfaces/IBridgeMessageSender.sol";
import {AssetMapper} from "../AssetMapper.sol";
import {IL2ToL2CrossDomainMessenger} from "./IL2ToL2CrossDomainMessenger.sol";
import {Constants} from "../../../lib/Constants.sol";

/// @title OpL2L2Sender
/// @notice Outbound message sender using OP Superchain L2ToL2CrossDomainMessenger
contract OpL2L2Sender is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IBridgeMessageSender {
    IL2ToL2CrossDomainMessenger public messenger;
    address public remoteReceiver; // Receiver contract on the remote chain
    uint32 public minGasLimit; // conservative gas limit for message execution
    AssetMapper public assetMapper; // optional mapper for asset translation

    event MessengerSet(address indexed messenger);
    event RemoteReceiverSet(address indexed remote);
    event MinGasLimitSet(uint32 minGas);
    event AssetMapperSet(address indexed mapper);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address messenger_, address remoteReceiver_, uint32 minGas_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        messenger = IL2ToL2CrossDomainMessenger(messenger_);
        remoteReceiver = remoteReceiver_;
        minGasLimit = minGas_ == 0 ? 1_000_000 : minGas_;
        emit MessengerSet(messenger_);
        emit RemoteReceiverSet(remoteReceiver_);
        emit MinGasLimitSet(minGasLimit);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setMessenger(address messenger_) external onlyRole(Constants.DEFAULT_ADMIN) {
        messenger = IL2ToL2CrossDomainMessenger(messenger_);
        emit MessengerSet(messenger_);
    }

    /// @notice Convenience: set messenger to OP Superchain L2ToL2CrossDomainMessenger predeploy
    function setMessengerToDefault() external onlyRole(Constants.DEFAULT_ADMIN) {
        messenger = IL2ToL2CrossDomainMessenger(Constants.OP_L2L2_MESSENGER_PREDEPLOY);
        emit MessengerSet(address(messenger));
    }

    function setRemoteReceiver(address remote_) external onlyRole(Constants.DEFAULT_ADMIN) {
        remoteReceiver = remote_;
        emit RemoteReceiverSet(remote_);
    }

    function setAssetMapper(address mapper) external onlyRole(Constants.DEFAULT_ADMIN) {
        assetMapper = AssetMapper(mapper);
        emit AssetMapperSet(mapper);
    }

    function setMinGasLimit(uint32 minGas_) external onlyRole(Constants.DEFAULT_ADMIN) {
        minGasLimit = minGas_;
        emit MinGasLimitSet(minGas_);
    }

    function sendDeposit(address user, address asset, uint256 amount, bytes32 depositId, bytes32 dstChain) external nonReentrant whenNotPaused {
        bytes memory payload = abi.encodeWithSignature(
            "onDepositMessage(address,address,uint256,bytes32,bytes32)", user, asset, amount, depositId, dstChain
        );
        messenger.sendMessage(remoteReceiver, payload, minGasLimit);
    }

    function sendWithdrawal(address user, address asset, uint256 amount, bytes32 withdrawalId, bytes32 dstChain) external nonReentrant whenNotPaused {
        // Translate base asset to satellite asset for the destination chain if mapper configured
        address satAsset = address(assetMapper) == address(0) ? asset : assetMapper.getSatelliteAsset(dstChain, asset);
        require(satAsset != address(0), "asset mapping missing");
        bytes memory payload = abi.encodeWithSignature(
            "onWithdrawalMessage(address,address,uint256,bytes32,bytes32)", user, satAsset, amount, withdrawalId, dstChain
        );
        messenger.sendMessage(remoteReceiver, payload, minGasLimit);
    }
}
