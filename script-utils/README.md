# On-chain Smoke Test (Chainweb EVM testnet chain 20)

This script opens and closes a tiny BTC-PERP position against the deployed MVP.

Prereqs:
- Node 18+
- pnpm or npm
- Environment:
  - RELAYER_PRIVATE_KEY (same funded key used for deployment)
  - RPC_5920 (optional; defaults to Chainweb testnet chain 20 RPC)

Setup:

```bash
# from repo root
cd script-utils
npm init -y
npm install ethers@^6.13 typescript ts-node @types/node
npx tsc --init --target ES2020 --module ES2020 --moduleResolution Node --esModuleInterop true
```

Run:

```bash
# export your env
export RELAYER_PRIVATE_KEY=0x...
# optional
export RPC_5920=https://api.chainweb.com/chainweb/0.0/testnet04/chain/20/evm

# execute
npx ts-node smoke.ts
```

What it does:
- Reads `deployments/5920.json`
- Uses zUSD to deposit into `MarginVaultV2`
- Opens a 2x long on BTC-PERP using 100 zUSD collateral
- Fetches position + margin ratio, then closes the position
- Prints final account equity in z18 units

Troubleshooting:
- "stale price" → set a fresh price in `SignedPriceOracle` via keeper account.
- "Not enough zUSD balance" → mint zUSD to your deployer or transfer from the deployer (MockzUSD is ownable; the owner is the deployer address).
- Reorg/rpc hiccups → re-run; script is idempotent for deposit but will error if no position exists on close.
