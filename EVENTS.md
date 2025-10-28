# Events Reference

This document catalogs the key events emitted by the Perp MVP smart contracts for indexing and frontend consumption.

## PerpEngine.sol

1. `OrderFilled(address account, bytes32 marketId, bytes32 fillId, bool isBuy, uint128 size, uint128 priceZ, uint128 feeZ, int128 fundingZ, int256 positionAfter)`
   - Emitted on every fill (recordFill or inline open/close).
   - `priceZ` and `feeZ` are denominated in zUSD 1e18.

   - Note: The `OrderFilled` event now also includes a non-indexed `bytes32 orderDigest` as the last parameter. This field is a canonical digest computed off-chain by the matching/settlement system and included in the `Fill` payload passed to `recordFill`. The contract does not recompute or verify this digest; it merely emits it for auditability and indexing.

   - Canonical orderDigest recipe (must be computed exactly as below by the off-chain system):

```
keccak256(abi.encode(
  bytes32("ZOOPX_ORDER_V1"),
  account,
  marketId,
  isBuy,
  sizeRaw,
  priceX18,
  feeZ,
  fundingZ,
  tsOrExpiry,
  clientOrderId
))
```

   - Field explanations and types used in the encoding above:
     - `bytes32("ZOOPX_ORDER_V1")`: domain/version marker to avoid cross-protocol collisions.
     - `account` (address): user account paying/receiving the fill.
     - `marketId` (bytes32): keccak256 market id string (e.g. keccak256("BTC-PERP")).
     - `isBuy` (bool): true for buy (long/close-buy), false for sell.
     - `sizeRaw` (uint256 / uint128): raw size in base units (the same units used in the `Fill.size` field).
     - `priceX18` (uint256 / uint128): price denominated in zUSD scaled to 1e18 (same as `Fill.priceZ`).
     - `feeZ` (uint256 / uint128): fee in zUSD scaled to 1e18 (same as `Fill.feeZ`).
     - `fundingZ` (int128): funding component in zUSD scaled to 1e18 (same as `Fill.fundingZ`).
     - `tsOrExpiry` (uint64): timestamp or expiry used by matcher for this order.
     - `clientOrderId` (bytes32): optional client-provided id (use zero bytes32 if unused).

   - Important: Keep type sizes consistent with the on-chain `Fill` structure when computing the digest (especially fixed-point scaling for price and fee). Use `abi.encode` (not `abi.encodePacked`) to match the canonical preimage layout above.

2. `PositionUpdated(address account, bytes32 marketId, int256 newSize, uint128 entryPriceZ, int256 unrealizedPnlZ)`
   - Mirrors position mutation with post-update size and cached entry price.
   - `unrealizedPnlZ` is zero for opens/adds; populated for closes/liquidations.

3. `Liquidation(address account, bytes32 marketId, uint128 closedSize, uint128 priceZ, uint128 penaltyZ)`
   - Full liquidation of a position. Penalty is computed on closed notional and transferred from the user's vault cross-balance to the `TreasurySpoke` via `MarginVaultV2.penalize`. A `PenaltyReceived` signal is emitted by the treasury.

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

3. `CreditBridged(address user, address asset, uint256 amount, bytes32 depositId)`
   - Emitted when the base-chain vault credits cross-margin balance for a user as a result of a verified bridge deposit message.

4. `DebitBridged(address user, address asset, uint256 amount, bytes32 withdrawalId)`
   - Emitted when the base-chain vault debits cross-margin balance for a user as part of a cross-chain withdrawal flow.

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

## BridgeAdapter.sol (base chain)

1. `BridgeCreditReceived(address user, address asset, uint256 amount, bytes32 depositId, bytes32 srcChain)`
   - A verified message was processed and the vault credited the user's cross balance.

2. `BridgeWithdrawalInitiated(address user, address asset, uint256 amount, bytes32 withdrawalId, bytes32 dstChain)`
   - A user initiated a cross-chain withdrawal; the vault debited their cross balance and an off-chain message should be sent to the satellite chain.

## EscrowGateway.sol (satellite chain)

1. `DepositEscrowed(address user, address asset, uint256 amount, bytes32 depositId, bytes32 dstChain)`
   - The gateway received tokens from the user and emitted a deposit intent destined for the base chain.

2. `WithdrawalReleased(address user, address asset, uint256 amount, bytes32 withdrawalId)`
   - The gateway released escrowed tokens to the user after a verified base-chain burn/withdrawal message.

## Indexing Tips

- Use `PositionUpdated` combined with `OrderFilled` to reconstruct per-trade PnL and position state transitions.
- Liquidation events include penalty amount, and the transfer to Treasury is executed via `MarginVaultV2.penalize`; downstream risk dashboards can treat penalty as realized loss at liquidation time.
- Funding accrual is implicit in position PnL via `getUnrealizedPnlZWithFunding`; only index `FundingUpdated` for historical funding rates chart.
- To build an account timeline: order by block/time across `Deposit`, `Withdraw`, `OrderFilled`, `Liquidation`, `PartialLiquidation` and `FundingUpdated`.

<!-- No deferred items for events at this time. -->
