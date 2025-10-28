// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IBridgeAdapter} from "../interfaces/IBridgeAdapter.sol";
import {AssetMapper} from "../AssetMapper.sol";
import {EscrowGateway} from "../../satellite/EscrowGateway.sol";
import {Constants} from "../../../lib/Constants.sol";

/// @title ViaReceiver
/// @notice Receiver for Via Labs router-delivered cross-chain messages; dispatches to BridgeAdapter or EscrowGateway
/// Security model: This contract gates by a trusted router address and checks a configured expectedRemoteSender
/// which must be enforced by the router's own origin authentication on the destination chain.
contract ViaReceiver is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    address public router;              // Trusted Via router on this chain
    address public expectedRemoteSender; // Expected source-side sender app (e.g., ViaMessageSender proxy on source chain)
    IBridgeAdapter public bridgeAdapter; // Base chain component
    EscrowGateway public escrowGateway;  // Satellite chain component
    AssetMapper public assetMapper;      // Mapping of assets per chain domain

    // replay protection (per unique deposit/withdrawal id + chain domain)
    mapping(bytes32 => bool) public processed;

    event RouterSet(address indexed router);
    event ExpectedRemoteSenderSet(address indexed remote);
    event BridgeAdapterSet(address indexed adapter);
    event EscrowGatewaySet(address indexed gateway);
    event AssetMapperSet(address indexed mapper);
    event MessageProcessed(bytes32 indexed id, bytes4 indexed selector);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin, address router_, address expectedRemoteSender_) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        router = router_;
        expectedRemoteSender = expectedRemoteSender_;
        emit RouterSet(router_);
        emit ExpectedRemoteSenderSet(expectedRemoteSender_);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    modifier onlyRouter() {
        require(msg.sender == router, "not router");
        _;
    }

    function setRouter(address router_) external onlyRole(Constants.DEFAULT_ADMIN) {
        router = router_;
        emit RouterSet(router_);
    }

    function setExpectedRemoteSender(address remote_) external onlyRole(Constants.DEFAULT_ADMIN) {
        expectedRemoteSender = remote_;
        emit ExpectedRemoteSenderSet(remote_);
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

    // Satellite -> Base: credit deposit
    // Includes the source-side sender address asserted by the router's origin verification.
    function onDepositMessage(
        address user,
        address satelliteAsset,
        uint256 amount,
        bytes32 depositId,
        bytes32 srcChain,
        address sourceSender
    ) external onlyRouter nonReentrant whenNotPaused {
        require(sourceSender == expectedRemoteSender, "bad source");
        bytes32 mid = keccak256(abi.encodePacked("dep", srcChain, depositId));
        require(!processed[mid], "replayed");
        processed[mid] = true;
        address baseAsset = address(assetMapper) == address(0) ? address(0) : assetMapper.getBaseAsset(srcChain, satelliteAsset);
        require(baseAsset != address(0), "asset mapping missing");
        bridgeAdapter.creditFromMessage(user, baseAsset, amount, depositId, srcChain);
        emit MessageProcessed(mid, this.onDepositMessage.selector);
    }

    // Base -> Satellite: release withdrawal
    function onWithdrawalMessage(
        address user,
        address satelliteAsset,
        uint256 amount,
        bytes32 withdrawalId,
        bytes32 srcChain,
        address sourceSender
    ) external onlyRouter nonReentrant whenNotPaused {
        require(sourceSender == expectedRemoteSender, "bad source");
        bytes32 mid = keccak256(abi.encodePacked("wd", srcChain, withdrawalId));
        require(!processed[mid], "replayed");
        processed[mid] = true;
        escrowGateway.completeWithdrawal(user, satelliteAsset, amount, withdrawalId);
        emit MessageProcessed(mid, this.onWithdrawalMessage.selector);
    }
}
