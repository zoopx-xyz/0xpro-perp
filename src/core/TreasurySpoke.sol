// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Constants} from "../../lib/Constants.sol";

contract TreasurySpoke is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    address public zUsdToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address admin) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.TREASURER, admin);
    }

    function setZUsdToken(address _zUsdToken) external onlyRole(Constants.DEFAULT_ADMIN) {
        zUsdToken = _zUsdToken;
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function balanceOf(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    // Optional helper for tests: settlement bot transfers token first, then calls this (no-op)
    function depositFromBot(address /*token*/, uint256 /*amount*/) external {
        // no-op in MVP; token should already be transferred to this contract
    }

    function sweepToHub(address token, uint256 amount, address to) external onlyRole(Constants.TREASURER) {
        IERC20(token).safeTransfer(to, amount);
    }

    function forwardFeesToSplitter(uint256 amount, address splitter) external onlyRole(Constants.FORWARDER_ROLE) {
        require(splitter != address(0), "invalid splitter");
        require(amount > 0, "invalid amount");
        require(zUsdToken != address(0), "zUSD not set");
        
        // Transfer zUSD to the fee splitter
        IERC20(zUsdToken).safeTransfer(splitter, amount);
        emit FeesForwarded(amount, splitter);
    }

    function receivePenalty(uint256 amount) external {
        // For MVP, funds should be transferred by caller before or after
        // This function signals penalty receipt
        require(amount > 0, "invalid amount");
        emit PenaltyReceived(amount);
    }

    event FeesForwarded(uint256 amount, address indexed splitter);
    event PenaltyReceived(uint256 amount);

    function receivePenalty(address token, uint256 amount) external {
        // For MVP, funds should be transferred by caller before or after; this function can be used to signal receipt
        // No access control to simplify tests
        (token); (amount);
    }

    uint256[50] private __gap;
}
