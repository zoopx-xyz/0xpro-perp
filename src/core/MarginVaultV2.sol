// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IMarginVault} from "./interfaces/IMarginVault.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IRiskConfig} from "./interfaces/IRiskConfig.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";
import {IPerpEngine} from "./interfaces/IPerpEngine.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title MarginVaultV2
/// @notice Multi-asset vault supporting cross and isolated balances; values normalized to 1e18 zUSD
contract MarginVaultV2 is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IMarginVault {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint128)) public crossBalances; // user => asset => amount
    mapping(address => mapping(bytes32 => mapping(address => uint128))) public isolatedBalances; // user => market => asset => amount

    ICollateralManager public collateralManager;
    IRiskConfig public riskConfig; // optional wiring for MMR
    IOracleRouter public oracleRouter; // for notional calc in MMR
    IPerpEngine public perpEngine; // for uPnL

    // reserved margin in zUSD units per user (internal 1e18) for simplicity
    mapping(address => uint256) public reservedZ;

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

    function setDeps(address _riskConfig, address _oracleRouter, address _perpEngine) external onlyRole(Constants.DEFAULT_ADMIN) {
        riskConfig = IRiskConfig(_riskConfig);
        oracleRouter = IOracleRouter(_oracleRouter);
        perpEngine = IPerpEngine(_perpEngine);
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
        // Equity/MRR guard
        require(_hasSufficientEquityAfterChange(msg.sender), "MarginVault: insufficient equity after withdraw");
        IERC20(asset).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, asset, amount, isolated, marketId);
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
    // convert asset amount (token units) to zUSD and add to reservedZ
    uint256 z = collateralManager.assetValueInZUSD(asset, amount);
        reservedZ[user] += z;
    }

    function release(address user, address asset, uint256 amount, bool isolated, bytes32 marketId) external override onlyRole(Constants.ENGINE) {
        if (isolated) {
            isolatedBalances[user][marketId][asset] += uint128(amount);
        } else {
            crossBalances[user][asset] += uint128(amount);
        }
    uint256 z = collateralManager.assetValueInZUSD(asset, amount);
        if (reservedZ[user] >= z) reservedZ[user] -= z; else reservedZ[user] = 0;
    }

    function accountEquityZUSD(address user) public view override returns (int256) {
        // Sum haircutted collateral across cross balances using CollateralManager asset index
        uint256 total;
        (bool ok, bytes memory data) = address(collateralManager).staticcall(abi.encodeWithSignature("getAssets()"));
        if (ok) {
            address[] memory assets = abi.decode(data, (address[]));
            for (uint256 i = 0; i < assets.length; i++) {
                address a = assets[i];
                uint256 amt = crossBalances[user][a];
                if (amt == 0) continue;
                try collateralManager.collateralValueInZUSD(a, amt) returns (uint256 v) {
                    total += v;
                } catch {}
            }
        }
        int256 uPnl = address(perpEngine) == address(0) ? int256(0) : IPerpEngine(perpEngine).getUnrealizedPnlZ(user);
        // subtract reservedZ from equity
        if (reservedZ[user] > 0) {
            if (total >= reservedZ[user]) total -= reservedZ[user];
            else total = 0;
        }
        return int256(total) + uPnl;
    }

    function _hasSufficientEquityAfterChange(address user) internal view returns (bool) {
        if (address(riskConfig) == address(0)) return true; // if not wired, skip
        int256 eq = accountEquityZUSD(user);
        // Compare against engine-computed MMR
        uint256 mmr = address(perpEngine) == address(0) ? 0 : IPerpEngine(address(perpEngine)).computeAccountMMRZ(user);
        return eq >= int256(mmr);
    }

    // Optional post-liquidation hook from engine
    function handlePostLiquidation(address user, uint256 releaseZ) external onlyRole(Constants.ENGINE) {
        // reduce reserved by amount and credit cross zUSD as unlocked (we just lower reservedZ)
        if (reservedZ[user] >= releaseZ) reservedZ[user] -= releaseZ; else reservedZ[user] = 0;
    }

    uint256[50] private __gap;
}
