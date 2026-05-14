# 07 — Integrations

> How Helix integrates with Safe, Aave V3, Pendle, and the Robinhood Chain RWA layer. Each integration is implemented as a per-protocol adapter with strict action types and post-condition checks.

---

## 1. Safe (Gnosis) Integration

Safe is the **single source of authorization** for Helix treasuries. Helix is implemented as a Safe Module.

### 1.1 Why a Safe Module (not a guard)

We considered:
- **Safe Guard** — runs before every Safe transaction. Too restrictive; would block all non-Helix Safe usage.
- **Safe Module** — extends Safe's executable surface without restricting normal Safe behavior. ✅ Chosen.
- **Plugin via SafenetSDK** — too tightly coupled to Safe's SDK; reduces portability to other multisigs in future.

The `HelixSafeModule` registers itself with the Safe at treasury creation. The module's only privileged call is `execTransactionFromModule(...)` against the TreasuryVault — which in turn checks the proposal flow.

### 1.2 Approval flow

```
Helix Proposal exists in ProposalRegistry, awaiting approval
              │
              ▼
       Safe signers review
              │
              ▼  (M-of-N signatures)
   Safe transaction: ProposalRegistry.approveProposal(id)
              │
              ▼
   ProposalRegistry marks as Approved, starts timelock
              │
              ▼  (24h later)
   anyone calls TreasuryVault.executeApproved(id)
              │
              ▼
   PolicyEngine re-validates → adapters dispatch → tax engine records
```

Safe signers are interacting with their normal Safe UI (Safe Web, Safe Mobile, Squad, Den, etc.). Helix surfaces the proposal context (policy, dry-run, predicted post-state) via the Safe Transaction Service's metadata feature.

### 1.3 Implementation files

- `contracts/solidity/integrations/HelixSafeModule.sol` — module registered with Safe
- `contracts/solidity/integrations/SafeProposalAdapter.sol` — formats proposals as Safe transactions
- `agent/src/safe/SafeTxBuilder.ts` — off-chain builder that creates correctly-formatted Safe transactions

### 1.4 Multisig requirements

Helix recommends but does not enforce:
- ≥3 signers, ≥2 threshold (3/5 is the sweet spot)
- Signers on different hardware wallet types (Ledger + Trezor + Keystone)
- Separate Guardian multisig (different signers, different threshold) for `cancelProposal` power

## 2. Aave V3 Integration

### 2.1 Supported Actions

| Action | Aave V3 call | Notes |
|---|---|---|
| `SUPPLY` | `Pool.supply(asset, amount, vault, 0)` | Vault receives aTokens |
| `WITHDRAW` | `Pool.withdraw(asset, amount, vault)` | Burns aTokens, returns underlying |
| `BORROW` | `Pool.borrow(asset, amount, mode, 0, vault)` | Requires collateral position; rare in treasury use |
| `REPAY` | `Pool.repay(asset, amount, mode, vault)` | |

### 2.2 Asset balance accounting

aTokens are rebasing. The vault's `getNAV()` queries `IPool.getReserveData(asset).aTokenAddress.balanceOf(vault)` for the live balance. PolicyEngine uses this live balance.

### 2.3 Hard constraint examples for Aave

```hxp
hard_constraint aave_exposure {
    require: share(state, AAVE_USDC_SUPPLY) <= 0.30
    on_violation: reject
}

hard_constraint aave_no_borrow {
    # treasury is conservative: lender only, never borrower
    require: balance(state, AAVE_USDC_DEBT) == 0
    on_violation: reject
}

hard_constraint aave_health_factor {
    require: aave_health_factor(state) >= 2.0 OR balance(state, AAVE_USDC_DEBT) == 0
    on_violation: reject
}
```

### 2.4 Circuit breaker

The `AaveAdapter` includes:
- Per-block deposit/withdraw rate limit
- Anomaly detector for reserve rate jumps (>10% per block triggers freeze)
- Forta listener integration to receive Aave-monitoring alerts

If circuit breaker trips, the adapter rejects new `SUPPLY` actions but allows `WITHDRAW` — making it safe to exit.

### 2.5 Implementation files

- `contracts/solidity/adapters/AaveAdapter.sol`
- `agent/src/simulators/AaveSimulator.ts`

## 3. Pendle Integration

### 3.1 Why Pendle

Pendle separates yield-bearing assets into Principal Tokens (PT) and Yield Tokens (YT). For treasury management, this matters because:

- **PT-USDC** gives fixed yield with known maturity → perfect for runway planning
- **YT-USDC** lets a treasury *speculate on yield direction* (typically not for conservative treasury, but supported)

### 3.2 Supported Actions

| Action | Pendle call | Notes |
|---|---|---|
| `BUY_PT` | swap USDC → PT-USDC (specific maturity) | Locks in fixed yield to maturity |
| `SELL_PT` | swap PT-USDC → USDC | Early exit; may have AMM slippage |
| `BUY_YT` | swap USDC → YT-USDC | Speculative; we'll mark this with `requires_yt_policy` |
| `SELL_YT` | swap YT-USDC → USDC | |
| `REDEEM_PT_AT_MATURITY` | redeem at face value | Free; called when PT matures |

### 3.3 Maturity awareness

PT tokens have fixed maturities (e.g. `PT-aUSDC-26DEC2026`). The PendleAdapter:

- Maintains a `maturitySchedule` for each held PT
- Emits a `PTMaturityApproaching` event 7 days before maturity
- Agent auto-proposes `REDEEM_PT_AT_MATURITY` when maturity reached

### 3.4 Hard constraint examples for Pendle

```hxp
hard_constraint pendle_concentration {
    require: share(state, PENDLE_PT_TOTAL) <= 0.40
    on_violation: reject
}

hard_constraint pendle_no_yt {
    # treasury is conservative: no YT speculation
    require: balance(state, PENDLE_YT_TOTAL) == 0
    on_violation: reject
}

hard_constraint pendle_maturity_diversification {
    # No more than 50% of PT in a single maturity bucket
    require: max_maturity_concentration(state) <= 0.50
    on_violation: reject
}
```

### 3.5 Implementation files

- `contracts/solidity/adapters/PendleAdapter.sol`
- `agent/src/simulators/PendleSimulator.ts`

## 4. Robinhood Chain RWA Integration

This is Helix's headline integration. Robinhood Chain testnet exposes tokenized US equities, ETFs, and (eventually) private equity/Treasuries.

### 4.1 Supported Asset Classes

| Class | Examples | RWA Adapter Method |
|---|---|---|
| Tokenized US Equities | tSPY, tAAPL, tGOOG | `BUY_RWA`, `SELL_RWA` |
| Tokenized ETFs | tQQQ, tVOO | `BUY_RWA`, `SELL_RWA` |
| Tokenized Treasuries (future) | tT-Bill-1Y | `BUY_RWA`, `REDEEM_RWA` |
| Tokenized Private Equity (future) | tOpenAI, tSpaceX | Specialized flow with KYC gates |

### 4.2 Corporate Action Handling

This is a Helix differentiator: most RWA platforms do not handle corporate actions cleanly. The Robinhood RWA adapter listens for:

- **Cash dividends** — when Robinhood issues a dividend distribution event, adapter receives USDC and emits `DividendReceived(asset, amount)`
- **Stock splits** — adapter detects token balance change, emits `StockSplit(asset, oldBalance, newBalance, ratio)` and adjusts cost basis in TaxEngine
- **Mergers / acquisitions** — token migration event; adapter performs swap to successor token, emits `MergerCompleted`
- **Delistings** — adapter triggers `EMERGENCY_REDEEM` proposal if a held asset gets delisted on the underlying market

### 4.3 Tax-Critical Hooks

Every corporate action triggers a `TaxEngine.recordCorporateAction(...)` call with full metadata for jurisdictional tax reporting. For US treasuries, this maps to 1099-DIV (dividends) and 1099-B (sales / mergers) categories.

### 4.4 Hard constraint examples for RWA

```hxp
hard_constraint rwa_total_cap {
    require: share(state, RWA_TOTAL) <= 0.50
    on_violation: reject
}

hard_constraint rwa_single_equity_cap {
    require: max_single_rwa_share(state) <= 0.10
    on_violation: reject
}

hard_constraint rwa_only_listed {
    # never hold RWA tokens whose underlying is delisted
    require: all_rwa_underlying_listed(state) == true
    on_violation: reject
}
```

### 4.5 Settlement timing

Robinhood Chain testnet documents `T+0` settlement for tokenized equities. Helix treats RWA buys/sells as atomic on-chain, but the TaxEngine records the settlement date for tax-lot accounting. This matters for wash-sale rule applicability in US tax treatment.

### 4.6 Implementation files

- `contracts/solidity/adapters/RobinhoodRWAAdapter.sol`
- `contracts/solidity/integrations/CorporateActionListener.sol` (event listener and dispatcher)
- `agent/src/simulators/RobinhoodSimulator.ts`
- `agent/src/listeners/CorporateActionWatcher.ts`

## 5. Oracle Aggregation

### 5.1 Sources by chain

| Chain | Primary | Secondary | Tertiary |
|---|---|---|---|
| Arbitrum One | Chainlink | Pyth | RedStone (v1+) |
| Arbitrum Sepolia | Chainlink mocks | Pyth Sepolia | — |
| Robinhood Chain | Robinhood RWA pricing oracle | Chainlink (for non-RWA) | — |

### 5.2 Aggregation logic

```
priceOf(asset):
    quotes = [feed.price() for feed in feeds[asset]]
    fresh = [q for q in quotes if now - q.timestamp < maxStaleness]
    require: len(fresh) >= minSources
    median = median(fresh)
    for q in fresh:
        require: abs(q.price - median) / median < maxDeviationBps
    return median, max(q.timestamp for q in fresh)
```

### 5.3 Special handling for RWA prices

RWA tokens trade against their underlying equity. The Robinhood RWA pricing oracle reports prices that reflect underlying market values during market hours and last-traded prices outside of hours. The aggregator treats this as a single trusted source for those tokens (since no second feed exists for tokenized stocks), but applies tighter freshness requirements (5 minutes during market hours, 4 hours outside).

## 6. MEV Protection

### 6.1 For SWAP actions

`ERC20Adapter.SWAP_UNISWAP_V3` and similar swap actions are routed through MEV protection by default:

- **Arbitrum**: Sequencer is currently a single Offchain Labs operator, which significantly reduces MEV risk versus Ethereum L1. We still route through Flashbots Protect-compatible endpoints when configured.
- **Slippage limits**: every swap action carries a `maxSlippageBps` parameter; the PolicyEngine enforces a global ceiling (typically `100 bps` = 1%)

### 6.2 For RWA actions

Robinhood Chain's permissioned design means MEV attacks are not currently a vector (no public mempool front-runner). We still apply slippage limits as a defense-in-depth.

## 7. Notification Channels

The agent's reporter pushes events to configurable channels.

### 7.1 Discord

```yaml
reporter:
  discord:
    webhook_url: "https://discord.com/api/webhooks/..."
    channels:
      proposal_submitted: true
      proposal_approved: true
      proposal_executed: true
      tax_event_recorded: false   # too noisy
      emergency: true
```

### 7.2 Slack

Same shape, different webhook format.

### 7.3 Email digest

```yaml
reporter:
  email:
    smtp_url: "smtp+ssl://..."
    recipients: ["treasury@org.example"]
    cadence: weekly
    include:
      - "all proposals"
      - "tax events summary"
      - "NAV summary"
```

### 7.4 Telegram

Bot integration via standard Telegram Bot API.

## 8. Forta Integration (v0.5+)

For per-adapter security monitoring, agents can subscribe to Forta detection bots:

```yaml
agent:
  forta:
    enabled: true
    subscriptions:
      - bot_id: "aave-monitoring-bot-id"
        action_on_alert: emergency_mode
      - bot_id: "pendle-monitoring-bot-id"
        action_on_alert: freeze_adapter
```

On a Forta alert matching subscription criteria, the agent automatically:
1. Submits an `EMERGENCY_REDEEM` proposal (which has fast-track approval)
2. Notifies the treasury owner via all configured channels
3. Logs the alert and the action taken

## 9. SDK Integration

The Helix SDK (`@helix/sdk` package) provides typed interfaces for:

```typescript
import { HelixClient } from "@helix/sdk";

const client = new HelixClient({
  chain: "arbitrum-sepolia",
  treasuryAddress: "0x...",
  signer,
});

// Read state
const state = await client.vault.getState();
const nav = await client.vault.getNAV();
const policies = await client.policyRegistry.getActivePolicies();

// Submit / track proposals
const proposalId = await client.proposalRegistry.submitProposal({...});
const status = await client.proposalRegistry.getStatus(proposalId);

// Subscribe to events
client.on("proposalApproved", (id) => { ... });

// Submit a custom policy update
await client.policyRegistry.proposeUpdate(newPolicyBytecode);
```

The SDK is what dashboards, agents, and third-party integrations build on top of.

## 10. Out-of-Band Integrations (Future)

We have *designed for* but not yet implemented:

- **Karpatkey / Llama / StableLab** professional treasury services — Helix as their execution surface
- **CCIP / LayerZero** cross-chain — for treasuries spanning multiple ecosystems
- **DeBank / Zerion** portfolio aggregators — read-only treasury views
- **Chainalysis / TRM Labs** compliance — sanctions screening as a hard constraint

These are noted in the [roadmap](./08-roadmap.md).
