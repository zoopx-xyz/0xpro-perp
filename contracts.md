Contracts (MVP deployments – chain-agnostic)

This document lists the MVP contracts, what each one does, how they fit together, and where to find their ABIs. Fill addresses after deployment to your target chain.

Core protocol
- PerpEngine (UUPS)
  - Address: <set on deploy>
  - Purpose: Settlement engine. Records fills, updates positions, enforces price staleness and slippage, routes fees to treasury/splitter, emits OrderFilled.
  - Key roles: DEFAULT_ADMIN, ENGINE_ADMIN, KEEPER, PAUSER_ROLE
  - ABI: out/PerpEngine.sol/PerpEngine.json

- MarginVaultV2 (UUPS)
  - Address: <set on deploy>
  - Purpose: Multi-asset cross/isolated margin vault. Holds user collateral, reserves/release margin for engine, checks equity/MMR on withdraw.
  - Key roles: DEFAULT_ADMIN, ENGINE (should be PerpEngine in prod), PAUSER_ROLE
  - ABI: out/MarginVaultV2.sol/MarginVaultV2.json

- MarketFactory (UUPS)
  - Address: <set on deploy>
  - Purpose: Optional helper for market creation/metadata.
  - Key roles: DEFAULT_ADMIN
  - ABI: out/MarketFactory.sol/MarketFactory.json

Risk, pricing, and oracles
- RiskConfig (UUPS)
  - Address: <set on deploy>
  - Purpose: Per-market risk params (IMR/MMR/liquidation penalty/fees/max leverage).
  - Key roles: DEFAULT_ADMIN, RISK_ADMIN
  - ABI: out/RiskConfig.sol/RiskConfig.json

- SignedPriceOracle (UUPS)
  - Address: <set on deploy>
  - Purpose: Keeper/signed price storage with staleness windows (EIP-712 for signed path).
  - Key roles: DEFAULT_ADMIN, PRICE_KEEPER
  - ABI: out/SignedPriceOracle.sol/SignedPriceOracle.json

- OracleRouter (UUPS)
  - Address: <set on deploy>
  - Purpose: Maps each base asset to its oracle (e.g., SignedPriceOracle). PerpEngine queries marks and staleness via this router.
  - Key roles: DEFAULT_ADMIN
  - ABI: out/OracleRouter.sol/OracleRouter.json

Collateral, fees, and funding
- CollateralManager (UUPS)
  - Address: <set on deploy>
  - Purpose: Collateral registry and valuation (enabled, LTV bps, decimals, oracle). Computes asset value and haircutted collateral in zUSD.
  - Key roles: DEFAULT_ADMIN, RISK_ADMIN
  - ABI: out/CollateralManager.sol/CollateralManager.json

- FundingModule (UUPS)
  - Address: <set on deploy>
  - Purpose: Tracks and updates per-market funding index; keepers call periodically.
  - Key roles: DEFAULT_ADMIN, KEEPER
  - ABI: out/FundingModule.sol/FundingModule.json

- TreasurySpoke (UUPS)
  - Address: <set on deploy>
  - Purpose: Holds zUSD fees; forwards to FeeSplitter.
  - Key roles: DEFAULT_ADMIN
  - ABI: out/TreasurySpoke.sol/TreasurySpoke.json

- FeeSplitterSpoke (UUPS)
  - Address: <set on deploy>
  - Purpose: Splits forwarded fees to recipients.
  - Key roles: DEFAULT_ADMIN
  - ABI: out/FeeSplitterSpoke.sol/FeeSplitterSpoke.json

Faucet and tokens
- MultiTokenFaucet (Ownable)
  - Address: <set on deploy>
  - Purpose: Admin-controlled faucet dispensing fixed per-token drops with 24h per-token per-wallet cooldown.
  - Owner actions: dispense, dispenseMany, setDrops, setCooldown, withdraw
  - ABI: out/MultiTokenFaucet.sol/MultiTokenFaucet.json

- MockzUSD (Ownable, 6d)
  - Address: <set on deploy>
  - Purpose: Settlement currency for testing.
  - ABI: out/MockzUSD.sol/MockzUSD.json

- MockERC20 tokens (Ownable)
  - mETH (18d): <set on deploy>
  - mWETH (18d): <set on deploy>
  - mBTC (8d): <set on deploy>
  - mWBTC (8d): <set on deploy>
  - mSOL (9d): <set on deploy>
  - mKDA (12d): <set on deploy>
  - mPOL (18d): <set on deploy>
  - mZPX (18d): <set on deploy>
  - mUSDC (6d): <set on deploy>
  - mUSDT (6d): <set on deploy>
  - mPYUSD (6d): <set on deploy>
  - mUSD1 (18d): <set on deploy>
  - ABI: out/MockERC20.sol/MockERC20.json

Market metadata (deployments)
- BTC-PERP
  - marketId: <set on deploy>
  - baseAsset: mBTC (<address>), baseDecimals: 8
  - Use: marketId is the on-chain key; engine uses baseAsset via OracleRouter for marks/staleness; risk/funding keyed by marketId.

Roles quick reference
- PerpEngine: DEFAULT_ADMIN (multisig), ENGINE_ADMIN (multisig), KEEPER (relayers), PAUSER_ROLE (multisig + break-glass)
- MarginVaultV2: DEFAULT_ADMIN (multisig), ENGINE (PerpEngine), PAUSER_ROLE (multisig + break-glass)
- RiskConfig: DEFAULT_ADMIN (multisig), RISK_ADMIN (risk-ops/multisig)
- SignedPriceOracle: DEFAULT_ADMIN (multisig), PRICE_KEEPER (price bots)
- OracleRouter: DEFAULT_ADMIN (multisig)
- CollateralManager: DEFAULT_ADMIN (multisig), RISK_ADMIN (risk-ops/multisig)
- FundingModule: DEFAULT_ADMIN (multisig), KEEPER (funding bot)
- TreasurySpoke, FeeSplitterSpoke, MarketFactory: DEFAULT_ADMIN (multisig)
- MultiTokenFaucet: Ownable (backend faucet signer or multisig)

Cross-chain components (base/satellite)
- BridgeAdapter (UUPS, base chain)
  - Address: <set on deploy>
  - Purpose: On the base chain, receives verified messages from your bridge provider and mints/burns margin credit in the vault.
  - Key roles: DEFAULT_ADMIN, BRIDGE_ROLE (on Vault), MESSAGE_RECEIVER_ROLE (who can call creditFromMessage)
  - Wire-up: setVault(vault), grant Vault.BRIDGE_ROLE to BridgeAdapter; your message receiver should hold MESSAGE_RECEIVER_ROLE on BridgeAdapter.
  - ABI: out/BridgeAdapter.sol/BridgeAdapter.json

- EscrowGateway (UUPS, satellite chain)
  - Address: <set on deploy>
  - Purpose: Custodies user tokens on satellite chains; emits deposit intents and releases tokens on verified withdrawals from base.
  - Key roles: DEFAULT_ADMIN, MESSAGE_SENDER_ROLE (who can send cross-chain messages), MESSAGE_RECEIVER_ROLE (who can call completeWithdrawal)
  - Wire-up: setSupportedAsset(asset, true); integrate your message bus to send deposit payloads and to authorize completeWithdrawal.
  - ABI: out/EscrowGateway.sol/EscrowGateway.json
- Cross-chain: Vault.BRIDGE_ROLE (held by BridgeAdapter), BridgeAdapter.MESSAGE_RECEIVER_ROLE (held by message verifier), EscrowGateway.MESSAGE_SENDER_ROLE and MESSAGE_RECEIVER_ROLE (held by your bridge adapters)

ABIs
All ABIs are in the Foundry build output under out/<Contract>.sol/<Contract>.json (the abi field of each JSON).

Notes
- Accepted collateral: CollateralManager.config(asset) must have enabled=true.
- Deposits: Use MarginVaultV2.deposit(asset, amount, isolated=false, marketId=0x0) for cross-margin.
- Price updates: Keepers push to SignedPriceOracle; engine fetches via OracleRouter.
- Fills: Keepers call PerpEngine.recordFill(Fill) using the correct marketId and canonical orderDigest.
