#!/usr/bin/env bash
set -euo pipefail

# Seed MultiTokenFaucet with extra amounts needed for 25k testers.
# Requires: cast, jq, RPC, FAUCET, and PK (owner private key) in environment.

RPC="${RPC:-https://evm-testnet.chainweb.com/chainweb/0.0/evm-testnet/chain/20/evm/rpc}"
FAUCET="${FAUCET:?set faucet address in FAUCET}"
PK="${PK:?set owner private key in PK}"

DEPLOY_JSON="${DEPLOY_JSON:-deployments/5920.json}"

token_addr() { jq -r "$1" "$DEPLOY_JSON"; }

METH=$(token_addr '.tokens.mETH')
MWETH=$(token_addr '.tokens.mWETH')
MBTC=$(token_addr '.tokens.mBTC')
MWBTC=$(token_addr '.tokens.mWBTC')
MSOL=$(token_addr '.tokens.mSOL')
MKDA=$(token_addr '.tokens.mKDA')
MPOL=$(token_addr '.tokens.mPOL')
MZPX=$(token_addr '.tokens.mZPX')
MUSDC=$(token_addr '.tokens.mUSDC')
MUSDT=$(token_addr '.tokens.mUSDT')
MPYUSD=$(token_addr '.tokens.mPYUSD')
MUSD1=$(token_addr '.tokens.mUSD1')

echo "Seeding faucet at $FAUCET using RPC=$RPC"

mint() {
  local token=$1; local amount=$2
  echo "mint $amount to faucet from token $token"
  cast send "$token" "mint(address,uint256)" "$FAUCET" "$amount" --rpc-url "$RPC" --private-key "$PK" >/dev/null
}

# Extras beyond initial 1,000,000 minted in Deploy.s.sol
# mKDA +124,000,000 @ 12d
mint "$MKDA" $((124000000 * 10**12))
# mPOL +124,000,000 @ 18d
mint "$MPOL" 124000000000000000000000000
# mZPX +124,000,000 @ 18d
mint "$MZPX" 124000000000000000000000000
# mUSDC +49,000,000 @ 6d
mint "$MUSDC" $((49000000 * 10**6))
# mUSDT +49,000,000 @ 6d
mint "$MUSDT" $((49000000 * 10**6))
# mPYUSD +49,000,000 @ 6d
mint "$MPYUSD" $((49000000 * 10**6))
# mUSD1 +49,000,000 @ 18d
mint "$MUSD1" 49000000000000000000000000

echo "Faucet seeding complete."
