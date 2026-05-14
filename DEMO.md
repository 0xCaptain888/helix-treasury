# Helix -- Live Demo Guide

> A judge should be able to reproduce this demo in under 10 minutes.
> All transactions are on Arbitrum Sepolia (chain ID 421614).

## What this demo shows

One complete treasury proposal lifecycle:

```
alice deposits mUSDC -> agent proposes transfer -> PolicyEngine approves
-> Safe approves -> timelock (1h simulated) -> execute -> TaxEngine records
```

## Prerequisites

```bash
git clone https://github.com/0xCaptain888/helix-treasury.git
cd helix-treasury
foundryup
cp .env.example .env
# Fill in: PRIVATE_KEY, ARBITRUM_SEPOLIA_RPC
```

## Contract addresses (Arbitrum Sepolia)

| Contract | Address |
|---|---|
| TreasuryVault | `0x2A46cF6493b377D45908254B0528e38990AA323f` |
| ProposalRegistry | `0x494960e21058290BB2F1328b6b837dCF26aA5DCb` |
| PolicyRegistry | `0x7058132Ba4aE19983c61590644F2943A3B7fDf80` |
| PolicyEngine (Stylus) | TBD -- deployed separately via cargo stylus |
| mUSDC (test token) | `0x9582d2dF303ec2B1fab104A77E249C05571fccC9` |
| Deployer/Safe | `0x2F9fDE6B6FB8d7353aB80F082f85F0d70B809C3b` |
| Guardian | `0xC7e424c1E4B346c06A35241e7BCa469477483683` |
| Agent EOA | `0x4c9Cef3bc7F5455d2581b717f115B2c76Fc1d092` |

## Step 1 -- Deposit mUSDC into vault

```bash
cast send 0x9582d2dF303ec2B1fab104A77E249C05571fccC9 \
  "approve(address,uint256)" \
  0x2A46cF6493b377D45908254B0528e38990AA323f \
  100000000000000000000000 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY

cast send 0x2A46cF6493b377D45908254B0528e38990AA323f \
  "deposit(address,uint256)" \
  0x9582d2dF303ec2B1fab104A77E249C05571fccC9 \
  100000000000000000000000 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY
```

## Step 2 -- Submit a proposal (agent posts bond first)

```bash
cast send 0x494960e21058290BB2F1328b6b837dCF26aA5DCb \
  "postBond()" \
  --value 0.01ether \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY

forge script scripts/solidity/Demo_SubmitProposal.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Step 3 -- Read the on-chain verdict

```bash
cast logs \
  --address 0x494960e21058290BB2F1328b6b837dCF26aA5DCb \
  --from-block latest \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  "ProposalSubmitted(bytes32,address,uint8)"
```

## Step 4 -- Approve (Safe multisig)

```bash
cast send 0x494960e21058290BB2F1328b6b837dCF26aA5DCb \
  "approveProposal(bytes32)" \
  <PROPOSAL_ID> \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $SAFE_KEY
```

## Step 5 -- Execute (after 1-hour timelock)

```bash
cast send 0x494960e21058290BB2F1328b6b837dCF26aA5DCb \
  "executeProposal(bytes32)" \
  <PROPOSAL_ID> \
  --rpc-url $ARBITRUM_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY
```

## Step 6 -- Verify on Arbiscan

All 5 steps above produce on-chain transactions viewable at:
`https://sepolia.arbiscan.io/address/0x2A46cF6493b377D45908254B0528e38990AA323f`

Look for: `Deposited`, `ProposalSubmitted`, `ProposalApproved`, `ProposalExecuted` events.
