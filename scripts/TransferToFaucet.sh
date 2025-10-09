#!/usr/bin/env bash
set -euo pipefail

# Transfer base amounts from owner to faucet for 25k tester totals minus what we minted as extras.
# This script sends the minimum of (1,000,000 tokens or total required) from the owner to the faucet,
# ensuring the faucet holds full totals when combined with SeedFaucet.sh extras.

RPC="${RPC:-https://evm-testnet.chainweb.com/chainweb/0.0/evm-testnet/chain/20/evm/rpc}"
FAUCET="${FAUCET:?set faucet address in FAUCET}"
PK="${PK:?set owner private key in PK}"
DEPLOY_JSON="${DEPLOY_JSON:-deployments/5920.json}"

addr() { jq -r "$1" "$DEPLOY_JSON"; }

METH=$(addr '.tokens.mETH')
MWETH=$(addr '.tokens.mWETH')
MBTC=$(addr '.tokens.mBTC')
MWBTC=$(addr '.tokens.mWBTC')
MSOL=$(addr '.tokens.mSOL')
MKDA=$(addr '.tokens.mKDA')
MPOL=$(addr '.tokens.mPOL')
MZPX=$(addr '.tokens.mZPX')
MUSDC=$(addr '.tokens.mUSDC')
MUSDT=$(addr '.tokens.mUSDT')
MPYUSD=$(addr '.tokens.mPYUSD')
MUSD1=$(addr '.tokens.mUSD1')

transfer() {
  local token=$1; local amount=$2
  echo "transfer $amount of $token to faucet"
  cast send "$token" "transfer(address,uint256)(bool)" "$FAUCET" "$amount" --rpc-url "$RPC" --private-key "$PK" >/dev/null
}

# Helper to compute min(totalNeeded, 1,000,000 in base units)
min_needed() {
  local total=$1; local oneMil=$2
  if [[ $total -lt $oneMil ]]; then echo $total; else echo $oneMil; fi
}

echo "Transferring base amounts to faucet $FAUCET"

# Totals needed in base units
TOT_METH=$((12500 * 10**18))
TOT_MWETH=$((12500 * 10**18))
TOT_MBTC=$((250 * 10**8))
TOT_MWBTC=$((250 * 10**8))
TOT_MSOL=$((250000 * 10**9))
TOT_MKDA=$((125000000 * 10**12))
TOT_MPOL=125000000000000000000000000
TOT_MZPX=125000000000000000000000000
TOT_MUSDC=$((50000000 * 10**6))
TOT_MUSDT=$((50000000 * 10**6))
TOT_MPYUSD=$((50000000 * 10**6))
TOT_MUSD1=50000000000000000000000000

# One million in base units per token
ONE_M_18=1000000000000000000000000
ONE_M_12=$((1000000 * 10**12))
ONE_M_9=$((1000000 * 10**9))
ONE_M_8=$((1000000 * 10**8))
ONE_M_6=$((1000000 * 10**6))

transfer "$METH"  $(min_needed $TOT_METH $ONE_M_18)
transfer "$MWETH" $(min_needed $TOT_MWETH $ONE_M_18)
transfer "$MBTC"  $(min_needed $TOT_MBTC $ONE_M_8)
transfer "$MWBTC" $(min_needed $TOT_MWBTC $ONE_M_8)
transfer "$MSOL"  $(min_needed $TOT_MSOL $ONE_M_9)
transfer "$MKDA"  $(min_needed $TOT_MKDA $ONE_M_12)
transfer "$MPOL"  $(min_needed $TOT_MPOL $ONE_M_18)
transfer "$MZPX"  $(min_needed $TOT_MZPX $ONE_M_18)
transfer "$MUSDC" $(min_needed $TOT_MUSDC $ONE_M_6)
transfer "$MUSDT" $(min_needed $TOT_MUSDT $ONE_M_6)
transfer "$MPYUSD" $(min_needed $TOT_MPYUSD $ONE_M_6)
transfer "$MUSD1" $(min_needed $TOT_MUSD1 $ONE_M_18)

echo "Transfers complete."
