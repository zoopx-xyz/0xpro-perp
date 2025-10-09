# Events Reference

This document catalogs the key events emitted by the Perp MVP smart contracts for indexing and frontend consumption.

## PerpEngine.sol

1. `OrderFilled(address account, bytes32 marketId, bytes32 fillId, bool isBuy, uint128 size, uint128 priceZ, uint128 feeZ, int128 fundingZ, int256 positionAfter)`
   - Emitted on every fill (recordFill or inline open/close).
   - `priceZ` and `feeZ` are denominated in zUSD 1e18.

2. `PositionUpdated(address account, bytes32 marketId, int256 newSize, uint128 entryPriceZ, int256 unrealizedPnlZ)`
   - Mirrors position mutation with post-update size and cached entry price.
   - `unrealizedPnlZ` is zero for opens/adds; populated for closes/liquidations.

3. `Liquidation(address account, bytes32 marketId, uint128 closedSize, uint128 priceZ, uint128 penaltyZ)`
   - Full liquidation of a position. Penalty transfer currently deferred (TODO) but amount is computed.

4. `PartialLiquidation(address account, bytes32 marketId, uint128 closedSize, uint128 priceZ, uint128 penaltyZ, uint128 remainingSize)`
   - Partial liquidation leaving a residual position; prunes market if remainingSize == 0.

5. `TradeExecuted(address user, bytes32 marketId, string symbol, bool isLong, uint256 amountBase, uint256 leverageX, uint256 entryPriceZ, uint256 exitPriceZ, uint256 collateralUsedToken, uint256 timestamp)`
   - Frontend-friendly aggregate event for open/close actions. `exitPriceZ` is zero on opens.

6. `PositionLiquidated(address user, bytes32 marketId, uint256 positionSizeClosed, uint256 collateralLostZ, uint256 liquidationFeeZ, uint256 timestamp)`
   - Normalized liquidation accounting event for indexing.

## MarginVaultV2.sol

1. `Deposit(address user, address asset, uint256 amount, bool isolated, bytes32 marketId)`
   - Cross or isolated deposit. `marketId` is zero for cross deposits.

2. `Withdraw(address user, address asset, uint256 amount, bool isolated, bytes32 marketId)`
   - Emits after equity/MMR guard passes.

## FundingModule.sol

1. `FundingUpdated(bytes32 marketId, int128 newIndex, int128 delta, uint64 timestamp)`
   - Cumulative funding index movement. Index is 1e18 scaled.

## FeeSplitterSpoke.sol

1. `FeesSplit(uint256 totalAmount, uint256 treasuryShare, uint256 insuranceShare, uint256 maintenanceShare, uint256 rewardsShare)`
   - Emitted after fee splitting logic; shares are token units (zUSD decimals).

## TreasurySpoke.sol

1. `FeesForwarded(uint256 amount, address splitter)`
   - Treasury forwarded fees to splitter for distribution.

## SignedPriceOracle.sol

1. `PriceSet(address asset, uint256 price, uint64 timestamp)`
   - Keeper-set price (legacy or signed) with timestamp.

2. `MaxStaleUpdated(uint64 newMaxStale)`
   - Updated staleness threshold; `0` means price never becomes stale (unless timestamp is zero).

## RiskConfig.sol

1. `MarketRiskSet(bytes32 marketId, uint16 imrBps, uint16 mmrBps, uint16 liqPenaltyBps, uint16 makerFeeBps, uint16 takerFeeBps, uint16 maxLev)`
   - Risk parameters for a market; all basis points.

## CollateralManager.sol

1. `AssetConfigSet(address asset, bool enabled, uint16 ltvBps, address oracle, uint8 decimals)`
   - Collateral asset registration or update.

## Indexing Tips

- Use `PositionUpdated` combined with `OrderFilled` to reconstruct per-trade PnL and position state transitions.
- Liquidation events include penalty amount even though transfer is deferred; downstream risk dashboards can treat penalty as realized loss placeholder.
- Funding accrual is implicit in position PnL via `getUnrealizedPnlZWithFunding`; only index `FundingUpdated` for historical funding rates chart.
- To build an account timeline: order by block/time across `Deposit`, `Withdraw`, `OrderFilled`, `Liquidation`, `PartialLiquidation` and `FundingUpdated`.

## Deferred / TODO

- Penalty transfer in liquidation events is not yet executed; will require safe deduction path from vault to treasury. Track issue in verification report.
