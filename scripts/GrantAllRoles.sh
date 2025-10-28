#!/usr/bin/env bash
set -euo pipefail

# Grant all relevant roles across contracts to the deployer EOA for MVP testing/demo.
# Requires: cast, jq, RPC, and PK or RELAYER_PRIVATE_KEY in env.

RPC="${RPC:?set RPC endpoint for target chain in RPC}"
DEPLOY_JSON="${DEPLOY_JSON:?path to deployments JSON for target chain}"

# Use PK, or fallback to RELAYER_PRIVATE_KEY (consistent with other scripts)
PK="${PK:-${RELAYER_PRIVATE_KEY:-}}"
: "${PK:?set PK or RELAYER_PRIVATE_KEY}"

ADDR() { jq -r "$1" "$DEPLOY_JSON"; }

# Proxies
ENGINE=$(ADDR '.proxies.PerpEngine')
VAULT=$(ADDR '.proxies.MarginVaultV2')
COLLAT=$(ADDR '.proxies.CollateralManager')
OROUTER=$(ADDR '.proxies.OracleRouter')
SORACLE=$(ADDR '.proxies.SignedPriceOracle')
RISK=$(ADDR '.proxies.RiskConfig')
FUND=$(ADDR '.proxies.FundingModule')
TREASURY=$(ADDR '.proxies.TreasurySpoke')
SPLITTER=$(ADDR '.proxies.FeeSplitterSpoke')
MKTFACTORY=$(ADDR '.proxies.MarketFactory')

SENDER=$(cast wallet address --private-key "$PK")
TARGET="${TARGET:-$SENDER}"

echo "RPC=$RPC"
echo "Granting roles to TARGET=$TARGET (tx sender=$SENDER)"

# Role IDs
ROLE_DEFAULT_ADMIN=0x0000000000000000000000000000000000000000000000000000000000000000
ROLE_KEEPER=$(cast keccak "KEEPER")
ROLE_ENGINE=$(cast keccak "ENGINE")
ROLE_ENGINE_ADMIN=$(cast keccak "ENGINE_ADMIN")
ROLE_RISK_ADMIN=$(cast keccak "RISK_ADMIN")
ROLE_PRICE_KEEPER=$(cast keccak "PRICE_KEEPER")
ROLE_PAUSER=$(cast keccak "PAUSER_ROLE")

grant() {
  local contract=$1; local role=$2; local name=$3
  if [[ -z "$contract" || "$contract" == "null" ]]; then return; fi
  echo "grantRole($name) on $contract -> $TARGET"
  cast send "$contract" "grantRole(bytes32,address)" "$role" "$TARGET" --rpc-url "$RPC" --private-key "$PK" >/dev/null
}

# PerpEngine
grant "$ENGINE" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN
grant "$ENGINE" "$ROLE_ENGINE_ADMIN" ENGINE_ADMIN
grant "$ENGINE" "$ROLE_KEEPER" KEEPER
grant "$ENGINE" "$ROLE_PAUSER" PAUSER_ROLE

# MarginVaultV2
grant "$VAULT" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN
grant "$VAULT" "$ROLE_ENGINE" ENGINE
grant "$VAULT" "$ROLE_PAUSER" PAUSER_ROLE

# CollateralManager
grant "$COLLAT" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN
grant "$COLLAT" "$ROLE_RISK_ADMIN" RISK_ADMIN

# SignedPriceOracle
grant "$SORACLE" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN
grant "$SORACLE" "$ROLE_PRICE_KEEPER" PRICE_KEEPER

# OracleRouter
grant "$OROUTER" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN

# RiskConfig
grant "$RISK" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN
grant "$RISK" "$ROLE_RISK_ADMIN" RISK_ADMIN

# FundingModule
grant "$FUND" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN
grant "$FUND" "$ROLE_KEEPER" KEEPER

# Treasury / Splitter / MarketFactory (admin only)
grant "$TREASURY" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN
grant "$SPLITTER" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN
grant "$MKTFACTORY" "$ROLE_DEFAULT_ADMIN" DEFAULT_ADMIN

echo "All grants submitted."
