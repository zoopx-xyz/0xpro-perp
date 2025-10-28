#!/usr/bin/env bash
set -euo pipefail

# Transfer base amounts from owner to faucet for 25k tester totals minus what we minted as extras.
# This script sends the minimum of (1,000,000 tokens or total required) from the owner to the faucet,
# ensuring the faucet holds full totals when combined with SeedFaucet.sh extras.

RPC="${RPC:?set RPC endpoint for target chain in RPC}"
FAUCET="${FAUCET:?set faucet address in FAUCET}"
# Support RELAYER_PRIVATE_KEY as a fallback for PK
PK="${PK:-${RELAYER_PRIVATE_KEY:-}}"
: "${PK:?set owner private key in PK or RELAYER_PRIVATE_KEY}"
DEPLOY_JSON="${DEPLOY_JSON:?path to deployments JSON for target chain}"

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

echo "Transferring base amounts to faucet $FAUCET"

# Totals needed in base units
TOT_METH=12500000000000000000000        # 12,500 * 10^18
TOT_MWETH=12500000000000000000000       # 12,500 * 10^18
TOT_MBTC=25000000000                    # 250 * 10^8
TOT_MWBTC=25000000000                   # 250 * 10^8
TOT_MSOL=250000000000000                # 250,000 * 10^9
TOT_MKDA=125000000000000000000          # 125,000,000 * 10^12 = 125 * 10^18
TOT_MPOL=125000000000000000000000000    # 125,000,000 * 10^18
TOT_MZPX=125000000000000000000000000    # 125,000,000 * 10^18
TOT_MUSDC=50000000000000                # 50,000,000 * 10^6
TOT_MUSDT=50000000000000                # 50,000,000 * 10^6
TOT_MPYUSD=50000000000000               # 50,000,000 * 10^6
TOT_MUSD1=50000000000000000000000000    # 50,000,000 * 10^18

# One million in base units per token
ONE_M_18=1000000000000000000000000
ONE_M_12=1000000000000000000        # 1,000,000 * 10^12 = 10^18
ONE_M_9=1000000000000000            # 1,000,000 * 10^9
ONE_M_8=100000000000                # 1,000,000 * 10^8
ONE_M_6=1000000000000               # 1,000,000 * 10^6

# For assets where total needed < 1,000,000, send the total; else send 1,000,000 base units.
transfer "$METH"  "$TOT_METH"
transfer "$MWETH" "$TOT_MWETH"
transfer "$MBTC"  "$TOT_MBTC"
transfer "$MWBTC" "$TOT_MWBTC"
transfer "$MSOL"  "$TOT_MSOL"
transfer "$MKDA"  "$ONE_M_12"
transfer "$MPOL"  "$ONE_M_18"
transfer "$MZPX"  "$ONE_M_18"
transfer "$MUSDC" "$ONE_M_6"
transfer "$MUSDT" "$ONE_M_6"
transfer "$MPYUSD" "$ONE_M_6"
transfer "$MUSD1" "$ONE_M_18"

echo "Transfers complete."
