// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IL2ToL2CrossDomainMessenger} from "./IL2ToL2CrossDomainMessenger.sol";
import {IBridgeAdapter} from "../interfaces/IBridgeAdapter.sol";
import {AssetMapper} from "../AssetMapper.sol";
import {EscrowGateway} from "../../satellite/EscrowGateway.sol";
import {Constants} from "../../../lib/Constants.sol";

/// @title OpL2L2Receiver
/// @notice Receiver for OP Superchain L2-to-L2 messages; dispatches to BridgeAdapter or EscrowGateway
contract OpL2L2Receiver is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    IL2ToL2CrossDomainMessenger public messenger;
    address public remoteSender; // Expected xDomainMessageSender
    IBridgeAdapter public bridgeAdapter; // base chain component
    EscrowGateway public escrowGateway;  // satellite chain component
    AssetMapper public assetMapper;      // mapping of assets per chain domain

    // replay protection
    mapping(bytes32 => bool) public processed;

    event MessengerSet(address indexed messenger);
    event RemoteSenderSet(address indexed remote);
    event BridgeAdapterSet(address indexed adapter);
    event EscrowGatewaySet(address indexed gateway);
    event AssetMapperSet(address indexed mapper);
    event MessageProcessed(bytes32 indexed id, bytes4 indexed selector);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address messenger_, address remoteSender_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        messenger = IL2ToL2CrossDomainMessenger(messenger_);
        remoteSender = remoteSender_;
        emit MessengerSet(messenger_);
        emit RemoteSenderSet(remoteSender_);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    modifier onlyMessenger() {
        require(msg.sender == address(messenger), "not messenger");
        _;
    }

    function setBridgeAdapter(address adapter) external onlyRole(Constants.DEFAULT_ADMIN) {
        bridgeAdapter = IBridgeAdapter(adapter);
        emit BridgeAdapterSet(adapter);
    }

    function setEscrowGateway(address gateway) external onlyRole(Constants.DEFAULT_ADMIN) {
        escrowGateway = EscrowGateway(gateway);
        emit EscrowGatewaySet(gateway);
    }

    function setAssetMapper(address mapper) external onlyRole(Constants.DEFAULT_ADMIN) {
        assetMapper = AssetMapper(mapper);
        emit AssetMapperSet(mapper);
    }

    function setMessenger(address messenger_) external onlyRole(Constants.DEFAULT_ADMIN) {
        messenger = IL2ToL2CrossDomainMessenger(messenger_);
        emit MessengerSet(messenger_);
    }

    function setRemoteSender(address remote_) external onlyRole(Constants.DEFAULT_ADMIN) {
        remoteSender = remote_;
        emit RemoteSenderSet(remote_);
    }

    /// @notice Convenience: set messenger to OP Superchain L2ToL2CrossDomainMessenger predeploy
    function setMessengerToDefault() external onlyRole(Constants.DEFAULT_ADMIN) {
        messenger = IL2ToL2CrossDomainMessenger(Constants.OP_L2L2_MESSENGER_PREDEPLOY);
        emit MessengerSet(address(messenger));
    }

    // Satellite -> Base: credit deposit
    function onDepositMessage(address user, address satelliteAsset, uint256 amount, bytes32 depositId, bytes32 srcChain)
        external
        onlyMessenger
        nonReentrant
        whenNotPaused
    {
        require(messenger.xDomainMessageSender() == remoteSender, "bad xSender");
        bytes32 mid = keccak256(abi.encodePacked("dep", srcChain, depositId));
        require(!processed[mid], "replayed");
        processed[mid] = true;
        address baseAsset = address(assetMapper) == address(0) ? address(0) : assetMapper.getBaseAsset(srcChain, satelliteAsset);
        require(baseAsset != address(0), "asset mapping missing");
        bridgeAdapter.creditFromMessage(user, baseAsset, amount, depositId, srcChain);
        emit MessageProcessed(mid, this.onDepositMessage.selector);
    }

    // Base -> Satellite: release withdrawal
    function onWithdrawalMessage(address user, address satelliteAsset, uint256 amount, bytes32 withdrawalId, bytes32 srcChain)
        external
        onlyMessenger
        nonReentrant
        whenNotPaused
    {
        require(messenger.xDomainMessageSender() == remoteSender, "bad xSender");
        bytes32 mid = keccak256(abi.encodePacked("wd", srcChain, withdrawalId));
        require(!processed[mid], "replayed");
        processed[mid] = true;
        // asset param expected by EscrowGateway is satellite asset; mapping validated at sender side
        escrowGateway.completeWithdrawal(user, satelliteAsset, amount, withdrawalId);
        emit MessageProcessed(mid, this.onWithdrawalMessage.selector);
    }
}
