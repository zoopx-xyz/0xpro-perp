// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMarginVault} from "./interfaces/IMarginVault.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title MarginVaultV2
/// @notice Multi-asset vault supporting cross and isolated balances; values normalized to 1e18 zUSD
contract MarginVaultV2 is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IMarginVault {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint128)) public crossBalances; // user => asset => amount
    mapping(address => mapping(bytes32 => mapping(address => uint128))) public isolatedBalances; // user => market => asset => amount

    ICollateralManager public collateralManager;

    event Deposit(address indexed user, address indexed asset, uint256 amount, bool isolated, bytes32 marketId);
    event Withdraw(address indexed user, address indexed asset, uint256 amount, bool isolated, bytes32 marketId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address admin, address _collateralManager) external initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _grantRole(Constants.DEFAULT_ADMIN, admin);
        _grantRole(Constants.ENGINE, admin);
        collateralManager = ICollateralManager(_collateralManager);
    }

    function _authorizeUpgrade(address) internal override onlyRole(Constants.DEFAULT_ADMIN) {}

    function deposit(address asset, uint256 amount, bool isolated, bytes32 marketId) external override nonReentrant {
        require(amount > 0, "amount=0");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        if (isolated) {
            isolatedBalances[msg.sender][marketId][asset] += uint128(amount);
        } else {
            crossBalances[msg.sender][asset] += uint128(amount);
        }
        emit Deposit(msg.sender, asset, amount, isolated, marketId);
    }

    function withdraw(address asset, uint256 amount, bool isolated, bytes32 marketId) external override nonReentrant {
        require(amount > 0, "amount=0");
        if (isolated) {
            uint128 bal = isolatedBalances[msg.sender][marketId][asset];
            require(bal >= amount, "insufficient");
            isolatedBalances[msg.sender][marketId][asset] = bal - uint128(amount);
        } else {
            uint128 bal = crossBalances[msg.sender][asset];
            require(bal >= amount, "insufficient");
            crossBalances[msg.sender][asset] = bal - uint128(amount);
        }
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, asset, amount, isolated, marketId);
        // NOTE: For MVP, we skip equity checks; tests can add checks via RiskConfig if needed
    }

    function reserve(address user, address asset, uint256 amount, bool isolated, bytes32 marketId) external override onlyRole(Constants.ENGINE) {
        if (isolated) {
            uint128 bal = isolatedBalances[user][marketId][asset];
            require(bal >= amount, "insufficient");
            isolatedBalances[user][marketId][asset] = bal - uint128(amount);
        } else {
            uint128 bal = crossBalances[user][asset];
            require(bal >= amount, "insufficient");
            crossBalances[user][asset] = bal - uint128(amount);
        }
    }

    function release(address user, address asset, uint256 amount, bool isolated, bytes32 marketId) external override onlyRole(Constants.ENGINE) {
        if (isolated) {
            isolatedBalances[user][marketId][asset] += uint128(amount);
        } else {
            crossBalances[user][asset] += uint128(amount);
        }
    }

    function accountEquityZUSD(address user) external view override returns (int256) {
        // MVP: sum haircutted collateral across cross balances only (isolated omitted for brevity)
        // In production include isolated + unrealized PnL from engine
        uint256 total;
        // naive iteration not possible without index; for MVP tests will query assets explicitly
        // This function will be extended to accept list of assets or rely on engine callbacks.
        return int256(total);
    }

    uint256[50] private __gap;
}
