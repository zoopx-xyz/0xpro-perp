// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IBridgeMessageSender} from "../interfaces/IBridgeMessageSender.sol";
import {IViaRouter} from "./IViaRouter.sol";
import {Constants} from "../../../lib/Constants.sol";

/// @title ViaMessageSender
/// @notice Outbound message sender integrating with Via Labs router; sends to a remote receiver that implements our receiver handlers
contract ViaMessageSender is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, IBridgeMessageSender {
    IViaRouter public router;
    uint64 public dstChainId;
    address public remoteReceiver;
    uint256 public callValue;     // optional msg.value sent with router call

    event RouterSet(address indexed router);
    event DstChainSet(uint64 dstChainId);
    event RemoteReceiverSet(address indexed remote);
    event CallValueSet(uint256 value);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address router_, uint64 dstChainId_, address remoteReceiver_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        router = IViaRouter(router_);
        dstChainId = dstChainId_;
        remoteReceiver = remoteReceiver_;
        emit RouterSet(router_);
        emit DstChainSet(dstChainId_);
        emit RemoteReceiverSet(remoteReceiver_);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function setRouter(address router_) external onlyRole(Constants.DEFAULT_ADMIN) { router = IViaRouter(router_); emit RouterSet(router_); }
    function setDstChain(uint64 id) external onlyRole(Constants.DEFAULT_ADMIN) { dstChainId = id; emit DstChainSet(id); }
    function setRemoteReceiver(address remote_) external onlyRole(Constants.DEFAULT_ADMIN) { remoteReceiver = remote_; emit RemoteReceiverSet(remote_); }
    function setCallValue(uint256 v) external onlyRole(Constants.DEFAULT_ADMIN) { callValue = v; emit CallValueSet(v); }

    function sendDeposit(address user, address asset, uint256 amount, bytes32 depositId, bytes32 dstChain) external nonReentrant whenNotPaused {
        bytes memory payload = abi.encodeWithSignature(
            "onDepositMessage(address,address,uint256,bytes32,bytes32,address)", user, asset, amount, depositId, dstChain, address(this)
        );
        router.xcall{value: callValue}(dstChainId, remoteReceiver, payload);
    }

    function sendWithdrawal(address user, address asset, uint256 amount, bytes32 withdrawalId, bytes32 dstChain) external nonReentrant whenNotPaused {
        bytes memory payload = abi.encodeWithSignature(
            "onWithdrawalMessage(address,address,uint256,bytes32,bytes32,address)", user, asset, amount, withdrawalId, dstChain, address(this)
        );
        router.xcall{value: callValue}(dstChainId, remoteReceiver, payload);
    }
}
