## Perp MVP

Contracts and tests for a Perp-only Hub+Spoke MVP.

Key features:
- UUPS upgradeable modules (Vault, Engine, Oracles, Risk, Funding, Treasury)
- Multi-asset CollateralManager with LTV haircuts and 1e18 zUSD accounting
- PerpEngine idempotent recordFill with canonical events
- SignedPriceOracle with keeper-set for tests and ECDSA support
- Mock tokens including settlement `mockzUSD` (6 decimals, ERC20Permit)

## Requirements
- Foundry installed

## Build & Test

```sh
forge build
forge test
```

## Deploy (MVP)

```sh
forge script scripts/Deploy.s.sol --broadcast --rpc-url <RPC_URL>
```

## Defaults
- Prices normalized to 1e18 zUSD
- Default LTVs: 50% non-stable, 100% stable
- Default oracle maxStale = 300s
- Maker fee = 5 bps, Taker fee = 7 bps (configurable in RiskConfig)

## TODO
- Implement full equity math in MarginVaultV2 (cross + isolated + PnL via engine)
- Wire FeeSplitter/Treasury flows and MarketFactory registration
- Expand tests for liquidation flows and staleness handling
