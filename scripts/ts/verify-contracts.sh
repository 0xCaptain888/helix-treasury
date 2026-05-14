#!/usr/bin/env bash
# =============================================================================
# scripts/ts/verify-contracts.sh
#
# Verifies all deployed Helix contracts on Arbiscan Sepolia.
# Run once after deployment. Idempotent — already-verified contracts are skipped.
#
# Prerequisites:
#   - ARBISCAN_API_KEY environment variable set
#   - ARBITRUM_SEPOLIA_RPC environment variable set (or defaults to public RPC)
#   - Contracts compiled (forge build already run)
#
# Usage:
#   export ARBISCAN_API_KEY=your_key_here
#   bash scripts/ts/verify-contracts.sh
#
# Individual contract (re-run one):
#   bash scripts/ts/verify-contracts.sh TreasuryVault
# =============================================================================

set -euo pipefail

RPC="${ARBITRUM_SEPOLIA_RPC:-https://sepolia-rollup.arbitrum.io/rpc}"
API_KEY="${ARBISCAN_API_KEY:-}"
CHAIN_ID=421614

if [ -z "$API_KEY" ]; then
  echo "❌  ARBISCAN_API_KEY is not set."
  echo "    Get a free key at: https://arbiscan.io/myapikey"
  echo "    Then: export ARBISCAN_API_KEY=your_key"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Helix — Arbiscan contract verification"
echo "  Network:  Arbitrum Sepolia (Chain ID $CHAIN_ID)"
echo "  RPC:      $RPC"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── Contract registry ────────────────────────────────────────────────────────
# Format: "ContractName:ContractAddress:SourcePath"
# SourcePath is relative to contracts/solidity/

declare -a CONTRACTS=(
  "OracleAggregator:0x6F4DF8979a8f18Ce3fD2ff941e5a3610E5cAfCa5:OracleAggregator.sol"
  "PolicyRegistry:0x7058132Ba4aE19983c61590644F2943A3B7fDf80:PolicyRegistry.sol"
  "ProposalRegistry:0x494960e21058290BB2F1328b6b837dCF26aA5DCb:ProposalRegistry.sol"
  "TreasuryVault:0x2A46cF6493b377D45908254B0528e38990AA323f:TreasuryVault.sol"
  "TaxEngine:0x8a8C3532359aAACb6C3a1060deF4938F6006c8F1:TaxEngine.sol"
  "ERC20Adapter:0x77472dADA40B8c30304a7FbbAf14e1b200A5c7FE:adapters/ERC20Adapter.sol"
  "AaveAdapter:0x1D77BBE8E921604c47CAb229Fc0727C5967F19a8:adapters/AaveAdapter.sol"
  "PendleAdapter:0x759aE549389eeDf1F055606fD9b72d071c7Ac3fa:adapters/PendleAdapter.sol"
  "RobinhoodRWAAdapter:0x41d158986CDAd44c7275A681a05215c9Aa1cAe1e:adapters/RobinhoodRWAAdapter.sol"
)

# Optional: single contract mode
SINGLE_TARGET="${1:-}"

PASS=0
FAIL=0
SKIP=0

for entry in "${CONTRACTS[@]}"; do
  IFS=: read -r name addr source_rel <<< "$entry"

  # Single contract mode: skip others
  if [ -n "$SINGLE_TARGET" ] && [ "$name" != "$SINGLE_TARGET" ]; then
    continue
  fi

  source_path="contracts/solidity/${source_rel}"
  full_name="${source_path}:${name}"

  echo -n "  Verifying $name ($addr) ... "

  # Run forge verify-contract
  output=$(forge verify-contract \
    "$addr" \
    "$full_name" \
    --chain-id "$CHAIN_ID" \
    --etherscan-api-key "$API_KEY" \
    --rpc-url "$RPC" \
    --watch \
    2>&1)

  exit_code=$?

  if echo "$output" | grep -q "Contract successfully verified"; then
    echo "✅  verified"
    PASS=$((PASS + 1))
  elif echo "$output" | grep -q "Already Verified"; then
    echo "✅  already verified (skipped)"
    SKIP=$((SKIP + 1))
  elif echo "$output" | grep -q "Contract source code already verified"; then
    echo "✅  already verified (skipped)"
    SKIP=$((SKIP + 1))
  else
    echo "❌  failed"
    echo "     Error: $(echo "$output" | tail -3)"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: ✅ $PASS verified  |  ✅ $SKIP already done  |  ❌ $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Arbiscan links:"
for entry in "${CONTRACTS[@]}"; do
  IFS=: read -r name addr source_rel <<< "$entry"
  echo "  $name:  https://sepolia.arbiscan.io/address/${addr}#code"
done
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "⚠️   Some contracts failed to verify."
  echo "    Common fixes:"
  echo "    1. Constructor args: forge verify-contract needs --constructor-args <hex>"
  echo "       Run: forge verify-contract <addr> <name> --constructor-args \$(cast abi-encode 'constructor(...)' arg1 arg2)"
  echo "    2. Compiler mismatch: check foundry.toml solc version matches deployment"
  echo "    3. API rate limit: wait 30s and retry"
  echo "    4. Already verifying: wait 60s for Arbiscan to process"
  exit 1
fi

echo "✅  All contracts verified. Evaluators can now read source at the links above."
