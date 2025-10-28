#!/usr/bin/env bash
set -euo pipefail

# Seed MultiTokenFaucet with extra amounts needed for 25k testers.
# Requires: cast, jq, RPC, FAUCET, and PK (owner private key) in environment.

RPC="${RPC:?set RPC endpoint for target chain in RPC}"
FAUCET="${FAUCET:?set faucet address in FAUCET}"
# Support RELAYER_PRIVATE_KEY as a fallback for PK
PK="${PK:-${RELAYER_PRIVATE_KEY:-}}"
: "${PK:?set owner private key in PK or RELAYER_PRIVATE_KEY}"

DEPLOY_JSON="${DEPLOY_JSON:?path to deployments JSON for target chain}"

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

# Derive sender address from PK and verify ownership of tokens to mint
SENDER=$(cast wallet address --private-key "$PK")
echo "Using sender $SENDER"

require_owner() {
  local token=$1; local sym=$2
  local owner
  owner=$(cast call "$token" 'owner()(address)' --rpc-url "$RPC")
  if [[ "${owner,,}" != "${SENDER,,}" ]]; then
    echo "ERROR: $sym owner $owner != sender $SENDER"
    exit 1
  fi
}

require_owner "$MKDA" "mKDA"
require_owner "$MPOL" "mPOL"
require_owner "$MZPX" "mZPX"
require_owner "$MUSDC" "mUSDC"
require_owner "$MUSDT" "mUSDT"
require_owner "$MPYUSD" "mPYUSD"
require_owner "$MUSD1" "mUSD1"

mint() {
  local token=$1; local amount=$2
  echo "mint $amount to faucet from token $token"
  cast send "$token" "mint(address,uint256)" "$FAUCET" "$amount" --rpc-url "$RPC" --private-key "$PK" >/dev/null
}

# Extras beyond initial 1,000,000 minted in Deploy.s.sol
# mKDA +124,000,000 @ 12d
mint "$MKDA" 124000000000000000000
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
