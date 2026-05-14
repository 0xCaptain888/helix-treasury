# 06 — Deployment Guide

> Step-by-step instructions for deploying Helix to Arbitrum Sepolia and Robinhood Chain testnet. Mainnet deployment is gated on audit completion (see [05-security-model.md](./05-security-model.md)).

---

## 1. Prerequisites

### Local environment

```bash
# Node toolchain
node --version    # >= 20.x
pnpm --version    # >= 9.x

# Rust + Stylus
rustc --version   # >= 1.80
rustup target add wasm32-unknown-unknown
cargo install --force cargo-stylus

# Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
forge --version

# Optional: Docker (for agent deployment)
docker --version
```

### Network access

- Arbitrum Sepolia testnet ETH: <https://faucet.quicknode.com/arbitrum/sepolia>
- Arbitrum Sepolia USDC: <https://faucet.circle.com>
- Robinhood Chain testnet faucet: see <https://docs.robinhoodchain.io> (link TBD; replace before publish)

### Accounts you need

| Account | Purpose | Where stored |
|---|---|---|
| **Deployer** | Deploys contracts | Hardware wallet or KMS |
| **Initial Safe owners** | Multisig signers (≥3 recommended) | Hardware wallets |
| **Guardian Safe owners** | Separate multisig for cancellation power | Hardware wallets (different people) |
| **Agent operator** | Runs the off-chain agent | KMS / Vault |

## 2. Repository Setup

```bash
git clone https://github.com/YOUR_ORG/helix.git
cd helix
pnpm install
cd contracts/stylus && cargo build --release && cd ../..
forge install
```

Create `.env`:

```env
# Required
ARB_SEPOLIA_RPC=https://sepolia-rollup.arbitrum.io/rpc
ROBINHOOD_TESTNET_RPC=https://testnet.robinhoodchain.io/rpc
DEPLOYER_PK=0xYOUR_KEY_OR_KMS_REF

# Safe addresses (deploy these first via safe.global)
SAFE_OWNER=0xYourMainSafe
SAFE_GUARDIAN=0xYourGuardianSafe

# Initial agent
AGENT_ADDRESS=0xYourAgentAddress

# Oracle feeds (Arbitrum Sepolia)
CHAINLINK_USDC_USD_FEED=0xPlaceholder
CHAINLINK_ARB_USD_FEED=0xPlaceholder
PYTH_USDC_USD_ID=0xPlaceholder

# Etherscan for verification
ARBISCAN_API_KEY=...
```

⚠️ **Never commit `.env`.** Use `.env.example` as a template.

## 3. Compile

```bash
# Solidity (Foundry)
forge build --sizes

# Stylus PolicyEngine
cd contracts/stylus/policy-engine
cargo stylus check
cargo stylus deploy --estimate-gas --private-key $DEPLOYER_PK --endpoint $ARB_SEPOLIA_RPC
```

`cargo stylus check` runs the Stylus checker that validates the WASM is deployable. It runs:
- Activation fee estimation
- Static analysis for forbidden opcodes
- Storage layout verification

## 4. Deploy to Arbitrum Sepolia

We deploy in three phases for safety: foundations first, then registry, then vault.

### Phase 1 — Foundations

```bash
forge script scripts/01_DeployFoundations.s.sol \
  --rpc-url $ARB_SEPOLIA_RPC \
  --private-key $DEPLOYER_PK \
  --broadcast --verify
```

This deploys:
- `OracleAggregator` (configured with Chainlink + Pyth feeds)
- `PolicyEngine` (Stylus contract, activated)
- `PolicyVerifier`
- `HardConstraintsLib`
- `AssetRegistry`

Output: `deployments/arbitrum-sepolia/foundations.json`

### Phase 2 — Registry layer

```bash
forge script scripts/02_DeployRegistry.s.sol \
  --rpc-url $ARB_SEPOLIA_RPC \
  --private-key $DEPLOYER_PK \
  --broadcast --verify
```

This deploys:
- `PolicyRegistry` (one per treasury template)
- `ProposalRegistry`

Output: `deployments/arbitrum-sepolia/registry.json`

### Phase 3 — Vault + Adapters

```bash
forge script scripts/03_DeployVault.s.sol \
  --rpc-url $ARB_SEPOLIA_RPC \
  --private-key $DEPLOYER_PK \
  --broadcast --verify
```

This deploys:
- `TreasuryVault`
- `TaxEngine`
- All adapters: `ERC20Adapter`, `AaveAdapter`, `PendleAdapter`, `RobinhoodRWAAdapter`
- `TreasuryFactory`

Output: `deployments/arbitrum-sepolia/vault.json`

### Phase 4 — Wire-up + first treasury

```bash
forge script scripts/04_BootstrapTreasury.s.sol \
  --rpc-url $ARB_SEPOLIA_RPC \
  --private-key $DEPLOYER_PK \
  --broadcast
```

This calls `TreasuryFactory.deployTreasury()` with a `DeployConfig` containing:
- Safe owner address
- Guardian address
- Initial policy bytecode (read from `policies/dao-quarterly-treasury.hxp.bin`)
- Initial hard constraints
- Initial assets (USDC, ARB)
- Initial agent address

Output: `deployments/arbitrum-sepolia/treasury-0001.json` (treasury contract address)

## 5. Deploy to Robinhood Chain Testnet

Robinhood Chain testnet is an Arbitrum Orbit L2. The deployment uses a dedicated script
that handles chain-specific configuration — particularly the absence of Chainlink feeds
(Robinhood Chain uses its own RWA pricing oracle) and the presence of native tokenized
equity assets (SPY, TBILL, AAPL).

### 5.1 Configure environment

Add to your `.env`:

```env
ROBINHOOD_TESTNET_RPC=https://rpc.testnet.chain.robinhood.com
ROBINHOOD_TESTNET_WS=wss://feed.testnet.chain.robinhood.com
```

### 5.2 Run the Robinhood Chain deploy script

```bash
forge script scripts/solidity/07_DeployRobinhoodChain.s.sol \
  --rpc-url $ROBINHOOD_TESTNET_RPC \
  --private-key $DEPLOYER_PK \
  --broadcast
```

This deploys:
- `OracleAggregator` (Pyth-only; no Chainlink on RBC testnet)
- `TreasuryFactory`
- `TreasuryVault` + `TaxEngine` (via factory, US_FIFO jurisdiction)

Deployed addresses are written to `deployments/robinhood-testnet.json`.

### 5.3 Register RWA tokens

After deployment, register the native RWA tokens (addresses from Robinhood Chain docs):

```bash
# Register tokenized SPY ETF
cast send $RBC_VAULT \
  "registerAsset((address,uint8,uint8,bool,bool,address,bool))" \
  "($RBC_SPY_ADDRESS,18,2,false,false,$RBC_RWA_ADAPTER,true)" \
  --rpc-url $ROBINHOOD_TESTNET_RPC \
  --private-key $SAFE_PK

# Register tokenized T-Bill
cast send $RBC_VAULT \
  "registerAsset((address,uint8,uint8,bool,bool,address,bool))" \
  "($RBC_TBILL_ADDRESS,18,2,false,false,$RBC_RWA_ADAPTER,true)" \
  --rpc-url $ROBINHOOD_TESTNET_RPC \
  --private-key $SAFE_PK
```

### 5.4 Configure RobinhoodRWAAdapter

The `RobinhoodRWAAdapter` includes a `CorporateActionListener` that subscribes to
Robinhood Chain's on-chain corporate action events (dividends, stock splits, mergers).
Configure it after deployment:

```bash
cast send $RBC_RWA_ADAPTER \
  "setVault(address)" $RBC_VAULT \
  --rpc-url $ROBINHOOD_TESTNET_RPC \
  --private-key $DEPLOYER_PK
```

### 5.5 Differences from Arbitrum Sepolia

| Item | Arbitrum Sepolia | Robinhood Chain testnet |
|---|---|---|
| Oracle sources | Chainlink + Pyth | Pyth only (+ RBC native oracle) |
| Native RWA assets | Mock tokens (mSPY, mTBILL) | Real tokenized SPY, TBILL, AAPL |
| Corporate actions | Simulated via mock | Real on-chain events from Robinhood Chain |
| Gas token | Sepolia ETH | Per Robinhood Chain docs |
| Block explorer | Arbiscan Sepolia | Robinhood Chain explorer |
| Deployment addresses | `deployments/arbitrum-sepolia.json` | `deployments/robinhood-testnet.json` |

⚠️ PolicyEngine remains on Arbitrum Sepolia. The Robinhood Chain vault calls the
Arbitrum-side engine via cross-chain messaging for policy evaluation. This is by design —
one PolicyEngine serves all chains.

## 6. Cross-Chain Coordination (v0.5)

For treasuries spanning both chains, deploy a `TreasuryVault` on each chain and a single off-chain Coordinator agent that watches both.

```bash
forge script scripts/05_DeployCrossChain.s.sol \
  --rpc-url $ARB_SEPOLIA_RPC \
  --private-key $DEPLOYER_PK \
  --broadcast
```

This configures the Arbitrum-native cross-chain messaging endpoints so that policies on one chain can reference state on the other (read-only).

⚠️ v0.5 does *not* support automated cross-chain action execution. Each chain's actions require their own multisig approval. This is intentional.

## 7. Post-Deployment Verification

After deployment, run:

```bash
pnpm verify:deployment --network arbitrum-sepolia
```

This script checks:
- All contracts deployed at expected addresses
- All contracts pass their constructor invariants
- Oracle feeds return non-zero, fresh prices
- PolicyEngine's `evaluate()` is callable with sample inputs
- ProposalRegistry's authorized agents list contains expected entries
- Vault's `getNAV()` returns 0 (empty treasury)
- Tax engine is wired to vault

## 8. First Funding

Fund the treasury (a deposit, not a proposal):

```bash
# Approve and deposit 10,000 USDC
forge script scripts/06_FundTreasury.s.sol \
  --sig "deposit(address,address,uint256)" \
  $TREASURY_VAULT $USDC_ADDRESS 10000000000 \
  --rpc-url $ARB_SEPOLIA_RPC \
  --private-key $DEPLOYER_PK \
  --broadcast
```

You should see:
- `TreasuryVault.getNAV()` returns ~10000 USDC equivalent
- `TaxEngine` has a `INTERNAL_TRANSFER` event recorded

## 9. Start the Agent

```bash
cd agent
cp config.example.yaml config.yaml
# edit config.yaml: vault address, RPC, agent key source
docker compose up -d
```

Agent will:
- Start in `MONITORING` mode by default
- Watch vault events
- Print "draft proposals" to logs without submitting

To move to `PROPOSING` mode (after a 30-day comfort period or via owner override):

```bash
# Via Helix CLI
pnpm cli treasury setMode --treasury $TREASURY_VAULT --mode proposing
```

## 10. Submitting the First Real Proposal

Once the agent is running and treasury is funded:

1. Wait for the agent's next `tick()` (default 4h, or trigger manually):
   ```bash
   pnpm cli agent tick --treasury $TREASURY_VAULT
   ```

2. Watch logs for `ProposalSubmitted` event with proposal ID.

3. View the proposal in Helix dashboard or via:
   ```bash
   pnpm cli proposal show --id <PROPOSAL_ID>
   ```

4. Have Safe signers review and approve via Safe UI.

5. After 24h timelock, anyone can execute:
   ```bash
   pnpm cli proposal execute --id <PROPOSAL_ID>
   ```

## 11. Deployment Cost Estimates (Arbitrum Sepolia)

These are approximate; check `deployments/*/gas-reports.json` for actuals.

| Component | Gas | Cost @ 0.1 gwei |
|---|---|---|
| `OracleAggregator` | ~1.2M | ~0.00012 ETH |
| `PolicyEngine` (Stylus, including activation fee) | ~3M + activation | ~0.0003 + 0.1 ETH activation |
| `PolicyRegistry` | ~1.5M | ~0.00015 ETH |
| `ProposalRegistry` | ~2M | ~0.0002 ETH |
| `TreasuryVault` | ~3M | ~0.0003 ETH |
| Adapters (each) | ~500k–1.5M | ~0.00005–0.00015 ETH |
| `TaxEngine` | ~1.5M | ~0.00015 ETH |
| `TreasuryFactory` | ~2M | ~0.0002 ETH |
| **Total foundations** | ~16M + activation | **~0.1015 ETH** |

For a single treasury bootstrap (after foundations are in place): ~0.001 ETH.

## 12. Mainnet Deployment Path (NOT v0.5)

We deliberately do not provide mainnet deployment scripts in v0.5. Mainnet path:

1. Complete buildathon submission
2. Engage Trail of Bits + OpenZeppelin (parallel audits)
3. Resolve all critical/high findings
4. Public audit reports
5. Bug bounty launch on Immunefi (4-week period before mainnet deployment)
6. Mainnet deployment with conservative initial parameters:
   - Lower timelock initially (12h) for incident response, raised to 24h after stability period
   - First treasury must have hard constraints reviewed by Helix team
   - First 90 days: rate-limited proposal frequency
7. Public deployment ceremony with reproducible builds

Target mainnet date: **Q3 2026**.

## 13. Troubleshooting

### "PolicyEngine reverts with `OracleStale`"
- Check that oracle feeds are configured for all assets the policy references
- Confirm `maxStaleness` setting is appropriate for testnet (Sepolia oracles update less frequently; we recommend `1 hour` for testnet)

### "Proposal execution reverts with `STALE_VERDICT`"
- The PolicyEngine re-evaluation at execution time failed. Check whether state changed during timelock (deposit/withdrawal).
- Re-trigger agent tick to produce a fresh proposal.

### "Stylus deploy fails with activation error"
- `cargo stylus check` first to validate
- Ensure deployer has enough testnet ETH for activation fee (~0.1 ETH on Sepolia)

### "Adapter execution reverts with `NotApproved`"
- Adapter has not been registered with vault
- Run `pnpm cli vault registerAdapter --vault $V --adapter $A`

### "Agent submits no proposals"
- Check agent logs for trigger evaluation
- Verify `MONITORING` vs `PROPOSING` mode
- Confirm agent has minimum bond posted

## 14. Disaster Recovery Drills

We recommend treasury owners practice these drills monthly:

1. **Emergency redeem drill** — submit and approve an `EMERGENCY_REDEEM` proposal, execute it within timelock
2. **Guardian cancel drill** — submit a normal proposal; have guardian cancel it during timelock
3. **Multisig key rotation** — rotate one signer key via Safe
4. **Agent key rotation** — rotate agent key via `setAuthorizedAgent`
5. **Policy update** — propose a tightening of a hard constraint, walk through 7-day timelock
