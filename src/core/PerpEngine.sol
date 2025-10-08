// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IMarginVault} from "./interfaces/IMarginVault.sol";
import {IPerpEngine} from "./interfaces/IPerpEngine.sol";
import {IRiskConfig} from "./interfaces/IRiskConfig.sol";
import {IOracleRouter} from "./interfaces/IOracleRouter.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {MathUtils} from "../../lib/MathUtils.sol";
import {ITreasurySpoke} from "./interfaces/ITreasurySpoke.sol";
import {IFeeSplitterSpoke} from "./interfaces/IFeeSplitterSpoke.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Constants} from "../../lib/Constants.sol";

/// @title PerpEngine (MVP)
contract PerpEngine is Initializable, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IPerpEngine {
    IMarginVault public vault;
    ITreasurySpoke public treasury;
    IFeeSplitterSpoke public feeSplitter;
    IRiskConfig public riskConfig;
    IERC20 public zUsd;
    IOracleRouter public oracleRouter;
    ICollateralManager public collateralManager;

    // market registry: marketId => base asset and decimals
    struct MarketMeta { address base; uint8 baseDecimals; string symbol; }
    mapping(bytes32 => MarketMeta) public markets;
    mapping(address => bytes32[]) private _openMarketsByAccount;

    // idempotency
    mapping(bytes32 => bool) public seenFill;

    // simple position: account => marketId => size (signed)
    mapping(address => mapping(bytes32 => int256)) public positions;
    // avg entry price per position in 1e18 zUSD
    mapping(address => mapping(bytes32 => uint128)) public entryPriceZ;

    event OrderFilled(address indexed account, bytes32 indexed marketId, bytes32 indexed fillId, bool isBuy, uint128 size, uint128 priceZ, uint128 feeZ, int128 fundingZ, int256 positionAfter);
    event PositionUpdated(address indexed account, bytes32 marketId, int256 newSize, uint128 entryPriceZ, int256 unrealizedPnlZ);
    event Liquidation(address indexed account, bytes32 marketId, uint128 closedSize, uint128 priceZ, uint128 penaltyZ);
    // Frontend-friendly events (JSON can be constructed off-chain from these fields)
    event TradeExecuted(
        address indexed user,
        bytes32 indexed marketId,
        string symbol,
        bool isLong,
        uint256 amountBase,
        uint256 leverageX,
        uint256 entryPriceZ,
        uint256 exitPriceZ,
        uint256 collateralUsedToken,
        uint256 timestamp
    );
    event PositionLiquidated(
        address indexed user,
        bytes32 indexed marketId,
        uint256 positionSizeClosed,
        uint256 collateralLostZ,
        uint256 liquidationFeeZ,
        uint256 timestamp
    );

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

    function setDeps(address _risk, address _oracleRouter, address _collateralManager, address _treasury, address _feeSplitter, address _zUsd) external onlyRole(Constants.ENGINE_ADMIN) {
        riskConfig = IRiskConfig(_risk);
        oracleRouter = IOracleRouter(_oracleRouter);
        collateralManager = ICollateralManager(_collateralManager);
        treasury = ITreasurySpoke(_treasury);
        feeSplitter = IFeeSplitterSpoke(_feeSplitter);
        zUsd = IERC20(_zUsd);
    }

    function registerMarket(bytes32 marketId, address base, uint8 baseDecimals) external onlyRole(Constants.ENGINE_ADMIN) {
        markets[marketId] = MarketMeta({base: base, baseDecimals: baseDecimals, symbol: ""});
    }

    function registerMarket(bytes32 marketId, address base, uint8 baseDecimals, string calldata symbol) external onlyRole(Constants.ENGINE_ADMIN) {
        markets[marketId] = MarketMeta({base: base, baseDecimals: baseDecimals, symbol: symbol});
    }

    function recordFill(Fill calldata f) external override onlyRole(Constants.KEEPER) nonReentrant {
        require(!seenFill[f.fillId], "dup fillId");
        seenFill[f.fillId] = true;

        // Check price staleness
        MarketMeta memory m = markets[f.marketId];
        require(m.base != address(0), "market not found");
        (, bool isStale) = oracleRouter.getPriceAndStale(m.base);
        require(!isStale, "PRICE_STALE");

        // Settlement-bot-first: ensure treasury holds fee zUSD
        if (address(treasury) != address(0) && address(zUsd) != address(0)) {
            require(treasury.balanceOf(address(zUsd)) >= uint256(f.feeZ), "fee not funded");
        }

        // Update positions
        int256 s = positions[f.account][f.marketId];
        int256 delta = f.isBuy ? int256(uint256(f.size)) : -int256(uint256(f.size));
        int256 newS = s + delta;
        positions[f.account][f.marketId] = newS;
        // update entry price (weighted avg for adds, reset on flip)
        uint128 ep = entryPriceZ[f.account][f.marketId];
        if (s == 0 || (s > 0 && newS < 0) || (s < 0 && newS > 0)) {
            // opening new or flipping side: set new entry
            entryPriceZ[f.account][f.marketId] = f.priceZ;
        } else if ((s > 0 && delta > 0) || (s < 0 && delta < 0)) {
            // adding to same direction: weighted avg
            uint256 absS = uint256(s > 0 ? s : -s);
            uint256 absD = uint256(delta > 0 ? delta : -delta);
            uint256 newAbs = absS + absD;
            uint256 wavg = (absS * uint256(ep) + absD * uint256(f.priceZ)) / newAbs;
            entryPriceZ[f.account][f.marketId] = uint128(wavg);
        } else {
            // reducing position: keep entry for remaining side
            // if position goes to zero, entry price remains; can be reset on next open
        }
        // track open markets list
        if (s == 0 && newS != 0) {
            _openMarketsByAccount[f.account].push(f.marketId);
        }

        // Reserve initial margin based on IMR bps and notional
        if (address(riskConfig) != address(0) && address(zUsd) != address(0)) {
            uint256 requiredMarginZ = IRiskConfig(riskConfig).requiredInitialMarginZ(
                f.marketId,
                m.base,
                uint256(f.size),
                m.baseDecimals,
                uint256(f.priceZ)
            );
            (, , , uint8 zDecs) = collateralManager.config(address(zUsd));
            uint256 tokenAmt = MathUtils.z18ToToken(requiredMarginZ, zDecs);
            vault.reserve(f.account, address(zUsd), tokenAmt, false, bytes32(0));
        }

        // Split fees (treasury already funded)
        if (address(feeSplitter) != address(0)) {
            feeSplitter.splitFees(uint256(f.feeZ));
        }

        emit OrderFilled(f.account, f.marketId, f.fillId, f.isBuy, f.size, f.priceZ, f.feeZ, f.fundingZ, newS);
        emit PositionUpdated(f.account, f.marketId, newS, f.priceZ, 0);
    }

    // User-facing helpers
    function openPosition(bytes32 marketId, bool isLong, uint256 collateralZToken, uint256 leverageX) external nonReentrant {
        MarketMeta memory m = markets[marketId];
        require(m.base != address(0), "market not found");
        (uint256 mark, bool isStale) = oracleRouter.getPriceAndStale(m.base);
        require(!isStale, "PRICE_STALE");
        require(leverageX > 0, "lev=0");
        // compute size in base token units: sizeRaw = (collateralZ18 * leverageX * 10^dec) / priceZ
        (, , , uint8 zDecs) = collateralManager.config(address(zUsd));
        uint256 collateralZ18 = MathUtils.tokenToZ18(collateralZToken, zDecs);
        uint256 sizeRaw = (collateralZ18 * leverageX * (10 ** m.baseDecimals)) / mark;
        require(sizeRaw > 0, "size=0");
        Fill memory f = Fill({
            fillId: keccak256(abi.encode(msg.sender, marketId, block.number, sizeRaw, isLong, collateralZToken)),
            account: msg.sender,
            marketId: marketId,
            isBuy: isLong,
            size: uint128(sizeRaw),
            priceZ: uint128(mark),
            feeZ: 0,
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });
        // Inline minimal settlement (subset of recordFill)
        require(!seenFill[f.fillId], "dup fillId");
        seenFill[f.fillId] = true;
        int256 s = positions[f.account][f.marketId];
        int256 delta = f.isBuy ? int256(uint256(f.size)) : -int256(uint256(f.size));
        int256 newS = s + delta;
        positions[f.account][f.marketId] = newS;
        uint128 ep = entryPriceZ[f.account][f.marketId];
        if (s == 0 || (s > 0 && newS < 0) || (s < 0 && newS > 0)) {
            entryPriceZ[f.account][f.marketId] = f.priceZ;
        } else if ((s > 0 && delta > 0) || (s < 0 && delta < 0)) {
            uint256 absS = uint256(s > 0 ? s : -s);
            uint256 absD = uint256(delta > 0 ? delta : -delta);
            uint256 newAbs = absS + absD;
            uint256 wavg = (absS * uint256(ep) + absD * uint256(f.priceZ)) / newAbs;
            entryPriceZ[f.account][f.marketId] = uint128(wavg);
        }
        if (s == 0 && newS != 0) { _openMarketsByAccount[f.account].push(f.marketId); }
        if (address(riskConfig) != address(0) && address(zUsd) != address(0)) {
            uint256 requiredMarginZ = IRiskConfig(riskConfig).requiredInitialMarginZ(
                f.marketId, m.base, uint256(f.size), m.baseDecimals, uint256(f.priceZ)
            );
            (, , , uint8 zDecs2) = collateralManager.config(address(zUsd));
            uint256 tokenAmt = MathUtils.z18ToToken(requiredMarginZ, zDecs2);
            vault.reserve(f.account, address(zUsd), tokenAmt, false, bytes32(0));
        }
        emit OrderFilled(f.account, f.marketId, f.fillId, f.isBuy, f.size, f.priceZ, f.feeZ, f.fundingZ, newS);
        emit PositionUpdated(f.account, f.marketId, newS, f.priceZ, 0);
        emit TradeExecuted(msg.sender, marketId, m.symbol, isLong, uint256(f.size), leverageX, mark, 0, collateralZToken, block.timestamp);
    }

    function closePosition(bytes32 marketId) external nonReentrant {
        int256 s = positions[msg.sender][marketId];
        require(s != 0, "no pos");
        MarketMeta memory m = markets[marketId];
        (uint256 mark, bool stale) = oracleRouter.getPriceInZUSD(m.base);
        require(!stale, "stale price");
        uint256 sz = uint256(s > 0 ? s : -s);
        bool isLong = s > 0;
        // Opposite trade to flatten
        Fill memory f = Fill({
            fillId: keccak256(abi.encode(msg.sender, marketId, block.number, sz, !isLong, "close")),
            account: msg.sender,
            marketId: marketId,
            isBuy: !isLong,
            size: uint128(sz),
            priceZ: uint128(mark),
            feeZ: 0,
            fundingZ: 0,
            ts: uint64(block.timestamp)
        });
        require(!seenFill[f.fillId], "dup fillId");
        seenFill[f.fillId] = true;
        // update position to zero
        positions[f.account][f.marketId] = 0;
        uint128 ep = entryPriceZ[f.account][f.marketId];
        entryPriceZ[f.account][f.marketId] = 0;
        // compute notional at entry and exit for PnL info (signed)
        uint256 notionalExit = MathUtils.notionalZFromSize(sz, m.baseDecimals, mark);
        uint256 notionalEntry = MathUtils.notionalZFromSize(sz, m.baseDecimals, uint256(ep));
        int256 pnl = int256(notionalExit) - int256(notionalEntry);
        if (!isLong) pnl = -pnl;
        // release IMR-equivalent
        if (address(riskConfig) != address(0)) {
            uint16 imr = IRiskConfig(riskConfig).getIMRBps(marketId);
            uint256 releaseZ = (notionalExit * imr) / 10_000;
            (, , , uint8 zDecs2) = collateralManager.config(address(zUsd));
            uint256 releaseTokenAmt = MathUtils.z18ToToken(releaseZ, zDecs2);
            vault.release(f.account, address(zUsd), releaseTokenAmt, false, bytes32(0));
        }
        emit OrderFilled(f.account, f.marketId, f.fillId, f.isBuy, f.size, f.priceZ, f.feeZ, f.fundingZ, 0);
        emit PositionUpdated(f.account, f.marketId, 0, f.priceZ, pnl);
        emit TradeExecuted(msg.sender, marketId, m.symbol, !isLong, uint256(f.size), 0, 0, mark, 0, block.timestamp);
    }

    function updatePositionMargin(bytes32 /*marketId*/, uint256 /*additionalCollateralToken*/) external {
        // Intentionally no-op at engine layer (cross-margin): users should deposit to Vault directly.
        // This function exists for frontend API symmetry.
    }

    function getPositionMarginRatioBps(address account, bytes32 marketId) external view returns (uint256) {
        int256 s = positions[account][marketId];
        if (s == 0) return type(uint256).max;
        MarketMeta memory m = markets[marketId];
        (uint256 mark, bool stale) = oracleRouter.getPriceInZUSD(m.base);
        if (stale) return 0;
        uint256 notionalZ = MathUtils.notionalZFromSize(uint256(s > 0 ? s : -s), m.baseDecimals, mark);
        int256 eq = vault.accountEquityZUSD(account);
        if (eq <= 0) return 0;
        return (uint256(eq) * 10_000) / notionalZ; // bps
    }

    function liquidate(address account, bytes32 marketId) external onlyRole(Constants.KEEPER) {
        int256 pos = positions[account][marketId];
        require(pos != 0, "no pos");
        if (address(riskConfig) != address(0)) {
            int256 eq = vault.accountEquityZUSD(account);
            require(eq < int256(computeAccountMMRZ(account)), "not liquidatable");
        }
        uint256 closedSize = uint256(pos > 0 ? pos : -pos);
        positions[account][marketId] = 0;
        entryPriceZ[account][marketId] = 0;
        // compute penalty on notional at current mark
        MarketMeta memory m = markets[marketId];
        (uint256 mark, bool stale) = oracleRouter.getPriceInZUSD(m.base);
        require(!stale, "stale price");
        uint256 closedNotionalZ = MathUtils.notionalZFromSize(closedSize, m.baseDecimals, mark);
        uint16 pbps = IRiskConfig(riskConfig).getLiqPenaltyBps(marketId);
        uint256 penaltyZ = (closedNotionalZ * pbps) / 10_000;
        if (address(zUsd) != address(0) && address(treasury) != address(0)) {
            IERC20(zUsd).transfer(address(treasury), penaltyZ);
        }
        // release reserved margin broadly (approximate: release equal to IMR at mark)
        uint16 imrBps = IRiskConfig(riskConfig).getIMRBps(marketId);
        uint256 releaseZ = (closedNotionalZ * imrBps) / 10_000;
        (, , , uint8 zDecs2) = collateralManager.config(address(zUsd));
        uint256 releaseTokenAmt = MathUtils.z18ToToken(releaseZ, zDecs2);
        vault.release(account, address(zUsd), releaseTokenAmt, false, bytes32(0));
        emit Liquidation(account, marketId, uint128(closedSize), uint128(mark), uint128(penaltyZ));
        emit PositionLiquidated(account, marketId, closedSize, releaseZ, penaltyZ, block.timestamp);
    }

    function computeAccountMMRZ(address account) public view returns (uint256 mmrZ) {
        bytes32[] memory ms = _openMarketsByAccount[account];
        for (uint256 i = 0; i < ms.length; i++) {
            bytes32 mid = ms[i];
            int256 s = positions[account][mid];
            if (s == 0) continue;
            MarketMeta memory m = markets[mid];
            (uint256 px, bool stale) = oracleRouter.getPriceInZUSD(m.base);
            if (stale) continue;
            uint256 notionalZ = MathUtils.notionalZFromSize(uint256(s > 0 ? s : -s), m.baseDecimals, px);
            uint16 mmr = IRiskConfig(riskConfig).getMMRBps(mid);
            mmrZ += (notionalZ * mmr) / 10_000;
        }
    }

    function getUnrealizedPnlZ(address account) external view returns (int256) {
        int256 total;
        bytes32[] memory ms = _openMarketsByAccount[account];
        for (uint256 i = 0; i < ms.length; i++) {
            bytes32 mid = ms[i];
            int256 s = positions[account][mid];
            if (s == 0) continue;
            MarketMeta memory m = markets[mid];
            (uint256 px, bool stale) = oracleRouter.getPriceInZUSD(m.base);
            if (stale) continue;
            uint128 ep = entryPriceZ[account][mid];
            uint256 notionalMark = MathUtils.notionalZFromSize(uint256(s > 0 ? s : -s), m.baseDecimals, px);
            uint256 notionalEntry = MathUtils.notionalZFromSize(uint256(s > 0 ? s : -s), m.baseDecimals, uint256(ep));
            int256 pnl = int256(notionalMark) - int256(notionalEntry);
            if (s < 0) pnl = -pnl; // invert for shorts
            total += pnl;
        }
        return total;
    }

    function getPosition(address account, bytes32 marketId) public view returns (int256) {
        return positions[account][marketId];
    }

    function getOpenMarketsForAccount(address account) external view returns (bytes32[] memory) {
        return _openMarketsByAccount[account];
    }

    uint256[50] private __gap;
}
