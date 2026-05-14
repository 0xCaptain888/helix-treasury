#!/bin/bash
# scripts/verify-all.sh
# Usage: ETHERSCAN_API_KEY=xxx RPC_URL=https://... ./scripts/verify-all.sh

set -e

CHAIN_ID=421614
ETHERSCAN_URL="https://api-sepolia.arbiscan.io/api"

ORACLE=0x6F4DF8979a8f18Ce3fD2ff941e5a3610E5cAfCa5
POLICY_REG=0x7058132Ba4aE19983c61590644F2943A3B7fDf80
PROPOSAL_REG=0x494960e21058290BB2F1328b6b837dCF26aA5DCb
VAULT=0x2A46cF6493b377D45908254B0528e38990AA323f
TAX=0x8a8C3532359aAACb6C3a1060deF4938F6006c8F1

SAFE=0x2F9fDE6B6FB8d7353aB80F082f85F0d70B809C3b
GUARDIAN=0xC7e424c1E4B346c06A35241e7BCa469477483683

echo "Verifying OracleAggregator..."
forge verify-contract $ORACLE \
  contracts/solidity/OracleAggregator.sol:OracleAggregator \
  --chain-id $CHAIN_ID \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --verifier-url $ETHERSCAN_URL

echo "Verifying PolicyRegistry..."
forge verify-contract $POLICY_REG \
  contracts/solidity/PolicyRegistry.sol:PolicyRegistry \
  --chain-id $CHAIN_ID \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --verifier-url $ETHERSCAN_URL

echo "Verifying ProposalRegistry..."
forge verify-contract $PROPOSAL_REG \
  contracts/solidity/ProposalRegistry.sol:ProposalRegistry \
  --chain-id $CHAIN_ID \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --verifier-url $ETHERSCAN_URL

echo "Verifying TreasuryVault..."
forge verify-contract $VAULT \
  contracts/solidity/TreasuryVault.sol:TreasuryVault \
  --chain-id $CHAIN_ID \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --verifier-url $ETHERSCAN_URL

echo "Verifying TaxEngine..."
forge verify-contract $TAX \
  contracts/solidity/TaxEngine.sol:TaxEngine \
  --chain-id $CHAIN_ID \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --verifier-url $ETHERSCAN_URL

echo ""
echo "All verifications submitted. Check Arbiscan in 1-2 minutes."
echo "https://sepolia.arbiscan.io/address/$VAULT#code"
