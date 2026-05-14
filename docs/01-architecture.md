# 01 — Architecture

> System architecture, data flow, and component boundaries for Helix v0.5.

## 1. Design Principles

Helix is designed against five non-negotiable principles. Every component must satisfy all five.

| # | Principle | What it means in practice |
|---|---|---|
| P1 | **Agent never moves money** | The Execution Agent only emits proposals. It has no signing key, no allowance, no execution path. |
| P2 | **Policy is the source of truth** | All treasury actions must pass PolicyEngine validation. No bypass paths exist, even for owners — owners can only update policies (which itself is gated). |
| P3 | **Hard constraints are inviolable** | Hard constraints declared at vault creation cannot be lowered or removed — only tightened. Enforced at the bytecode level by PolicyEngine. |
| P4 | **Every action is reproducible** | Every executed action stores: policy hash, market snapshot, simulation result, multisig confirmation, post-state. Anyone can re-run and verify. |
| P5 | **Failure modes degrade safely** | Loss of Execution Agent = treasury is frozen but safe. Loss of multisig = treasury is recoverable through emergency timelock path. Loss of policy = previous policy stays active. |

## 2. Component Map

```
┌────────────────────── OFF-CHAIN ──────────────────────┐    ┌────────────── ON-CHAIN (Arbitrum) ──────────────┐
│                                                       │    │                                                  │
│   ┌─────────────┐      ┌──────────────────────┐       │    │                                                  │
│   │  Helix UI   │      │   Execution Agent    │       │    │      ┌────────────────────────────────┐          │
│   │  Dashboard  │      │   (TS/Node service)  │       │    │      │   PolicyEngine                  │         │
│   └──────┬──────┘      │                      │       │    │      │   (Stylus, Rust)                │         │
│          │             │   • Market monitor   │       │    │      │                                  │         │
│   ┌──────▼──────┐      │   • Policy evaluator │       │    │      │   evaluate(proposal) → verdict   │         │
│   │  Helix SDK  │      │   • Simulator        ├───────┼────┼─────▶│   • static guards                │         │
│   │  (TS)       │      │   • Proposal builder │       │    │      │   • soft policies                │         │
│   └──────┬──────┘      │   • Reporter         │       │    │      │   • hard constraints             │         │
│          │             │                      │       │    │      │   • deterministic verdict        │         │
│          │             └──────────┬───────────┘       │    │      └────────────────┬─────────────────┘         │
│          │                        │                   │    │                       │                          │
│          │                        │  proposal()       │    │                       │ verdict                  │
│          │                        └──────────────────┼────┼──────────────┐        │                          │
│          │                                            │    │              ▼        ▼                          │
│          │                                            │    │      ┌──────────────────────────────────┐        │
│          │       multisig sign                        │    │      │   ProposalRegistry                │        │
│          └────────────────────────────────────────────┼────┼─────▶│   (Solidity)                      │        │
│                                                       │    │      │                                   │        │
│                                                       │    │      │   • stores proposals + verdicts   │        │
│                                                       │    │      │   • timelock + Safe gate          │        │
│                                                       │    │      │   • emits events                  │        │
│                                                       │    │      └────────────────┬──────────────────┘        │
│                                                       │    │                       │ executeApproved()         │
│                                                       │    │                       ▼                          │
│                                                       │    │      ┌──────────────────────────────────┐        │
│                                                       │    │      │   TreasuryVault                   │        │
│                                                       │    │      │   (Solidity)                      │        │
│                                                       │    │      │                                   │        │
│                                                       │    │      │   • multi-asset custody           │        │
│                                                       │    │      │   • dispatches to adapters        │        │
│                                                       │    │      │   • post-execution accounting     │        │
│                                                       │    │      └────────────────┬──────────────────┘        │
│                                                       │    │           ┌───────────┼───────────┐               │
│                                                       │    │           ▼           ▼           ▼               │
│                                                       │    │      AaveAdapter  PendleAdapter  RWAAdapter        │
│                                                       │    │                                                    │
│                                                       │    │      ┌──────────────────────────────────┐         │
│                                                       │    │      │   TaxEngine                       │         │
│                                                       │    │      │   • hooks on every execution     │         │
│                                                       │    │      │   • produces tax events           │         │
│                                                       │    │      └──────────────────────────────────┘         │
│                                                       │    │                                                    │
└───────────────────────────────────────────────────────┘    └────────────────────────────────────────────────────┘
```

## 3. Data Flow: Anatomy of One Treasury Action

Walk through what happens when the policy says *"if USDC balance > 18 months runway, allocate excess 50/30/20 to BENJI / SPY-token / Aave USDC supply"* and a new payment arrives that triggers this.

### Step 1 — Market monitoring (off-chain)

The **Execution Agent** runs on a fixed cadence (default: every 4 hours) and on key events (deposit, withdrawal, oracle price change > 2%). On each tick:

```
agent.tick():
    state ← TreasuryVault.getState()
    market ← OracleAggregator.snapshot()
    policies ← PolicyRegistry.getActive(treasury)
    for p in policies:
        if p.shouldTrigger(state, market):
            proposal ← p.buildProposal(state, market)
            simulation ← simulator.run(proposal, state, market)
            if simulation.passes:
                submit(proposal)
```

Critical: the agent's role is to *find candidate actions*. It does not decide whether the action is allowed — that's the PolicyEngine's job.

### Step 2 — Proposal submission (on-chain)

Agent submits a proposal to `ProposalRegistry.submitProposal()`:

```solidity
struct Proposal {
    bytes32 policyHash;           // which policy triggered this
    bytes32 marketStateHash;      // commitment to market data
    Action[] actions;             // ordered list of treasury operations
    bytes32 dryRunResultHash;     // commitment to simulated outcome
    uint256 expiresAt;            // proposal validity window
    bytes agentSignature;         // agent identity (for accountability)
}
```

The agent's signature is not authorization — it's *attribution*. If a bad proposal slips through, we can trace which agent built it.

### Step 3 — On-chain policy validation

`ProposalRegistry.submitProposal()` immediately calls `PolicyEngine.evaluate(proposal)`:

```rust
// stylus pseudocode
pub fn evaluate(proposal: Proposal) -> Verdict {
    let policy = registry.get(proposal.policy_hash)?;
    let market = oracle.snapshot();

    // 1. Verify market state matches commitment within tolerance
    assert!(market.hash().close_to(proposal.market_state_hash, TOLERANCE));

    // 2. Run hard constraints (cannot be bypassed)
    for c in policy.hard_constraints {
        if !c.holds_after(proposal.actions, state) {
            return Verdict::Reject(c.id);
        }
    }

    // 3. Run soft policy logic
    let computed = policy.compute(state, market);
    if !computed.matches(proposal.actions) {
        return Verdict::Reject("proposal does not match policy output");
    }

    Verdict::Approve { policy_hash, computed_hash }
}
```

If the verdict is `Reject`, the proposal is discarded with an event. If `Approve`, the proposal is stored in `ProposalRegistry` and a `ProposalApproved` event is emitted.

### Step 4 — Multisig review

The Helix UI shows the proposal to the Safe multisig signers:

- The exact actions to execute
- The policy that justified it (with link to policy definition)
- The dry-run simulation result (predicted post-execution state)
- The market state at proposal time
- Any tax events that will be generated

Signers approve via the standard Safe flow. **There is no Helix-specific signing UI** — we hook into Safe Transaction Service. This means signers use the tools they already trust.

### Step 5 — Timelock

After multisig approval, the proposal enters a configurable timelock (default 24 hours). During this window:

- The proposal is publicly visible on-chain
- Any party can call `cancelProposal()` if they hold the `GUARDIAN_ROLE`
- Anyone can observe and prepare to react

This is critical for two reasons. First, it gives the community time to spot a malicious proposal that somehow got multisig approval. Second, it makes Helix usable for organizations with delayed governance (DAOs with quorum mechanisms).

### Step 6 — Execution

After timelock expires, `TreasuryVault.executeApproved(proposalId)` can be called by anyone (it's permissionless — the proposal has already been authorized). The vault:

1. Re-checks that the proposal is still `Approved` and within validity window
2. Re-runs `PolicyEngine.evaluate()` with current state (to prevent stale execution)
3. Dispatches each action to its adapter
4. Hooks into `TaxEngine.recordExecution()` for accounting
5. Emits `ProposalExecuted` with the actual post-state

The double-check at execution time is non-negotiable. Market state may have moved during timelock, and an action that was safe at proposal time may now violate hard constraints. If so, execution reverts and the proposal expires.

### Step 7 — Reporting

The Execution Agent (in its reporter role) picks up the `ProposalExecuted` event and:

- Updates treasury dashboard
- Generates the tax events report
- Notifies the treasurer via the configured channel (Discord, Slack, email)

## 4. Component Boundaries

| Component | Lives | Trusted to | Cannot |
|---|---|---|---|
| **Execution Agent** | off-chain | propose, simulate, report | move funds; override policies |
| **PolicyEngine** (Stylus) | on-chain | evaluate, return verdicts | hold funds; bypass hard constraints |
| **ProposalRegistry** | on-chain | store proposals, manage timelock | execute actions directly |
| **TreasuryVault** | on-chain | custody, dispatch to adapters | accept actions without PolicyEngine approval |
| **Safe (multisig)** | on-chain (external) | approve/reject proposals | propose; bypass timelock |
| **Adapters** | on-chain | translate generic actions → protocol calls | be called directly by anything other than TreasuryVault |
| **TaxEngine** | on-chain | record events, classify by jurisdiction | reject or modify actions |
| **Oracle Aggregator** | on-chain | provide market snapshots | hold treasury authority |

## 5. Trust Model

Helix is honest about what it trusts and what it does not.

**What Helix trusts:**
- Arbitrum (Sepolia, then mainnet) for finality and fraud proofs
- Safe contracts for multisig logic (battle-tested)
- Chainlink + Pyth oracles for prices, with deviation guard
- The treasury owner to set policies they intend

**What Helix does *not* trust:**
- The Execution Agent — it has no privileged role. Compromising the agent compromises *liveness* (no new proposals), not *safety* (existing policy still holds).
- LLMs — the agent uses LLMs for natural language → policy translation, but the resulting policy is **always shown to humans in DSL form before being committed**. LLM hallucination cannot insert policy that humans did not approve.
- Adapter protocols — we treat Aave, Pendle, and RWA issuers as untrusted external systems. Failures contained via per-adapter circuit breakers.

## 6. Why Stylus for PolicyEngine

The PolicyEngine is the single most important contract in the system. We chose Arbitrum Stylus (Rust) for it for four reasons:

1. **Gas efficiency** — Policy evaluation involves loops over constraints, arithmetic on multi-asset balances, and hash computation. Stylus is 10x cheaper for this workload than Solidity.
2. **Determinism guarantees** — Rust's type system and the WASM execution environment give us stronger reasoning about deterministic behavior than the EVM.
3. **Testability** — The Stylus PolicyEngine can be unit-tested in native Rust environments (without forking a chain), allowing property-based testing with `proptest`.
4. **Evaluator pattern fit** — A pure evaluation function is the textbook use case for Stylus. We are not doing anything weird; we are using the right tool.

The rest of the system (custody, adapters, registry) remains Solidity because that's where the ecosystem libraries live.

## 7. Cross-Chain Architecture (v0.5)

For treasuries that span Arbitrum One and Robinhood Chain (e.g. a DAO holding ARB + tokenized SPY):

```
                          ┌─────────────────────┐
                          │   Helix Coordinator │
                          │  (off-chain agent)  │
                          └──────────┬──────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              │                      │                      │
              ▼                      ▼                      ▼
   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
   │  TreasuryVault   │   │  TreasuryVault   │   │  TreasuryVault   │
   │  (Arbitrum One)  │   │ (Robinhood Chain)│   │ (other Orbit L2) │
   └──────────────────┘   └──────────────────┘   └──────────────────┘
```

Each chain has its own TreasuryVault + PolicyEngine. The Coordinator agent maintains a unified view and proposes cross-chain actions using:
- **Arbitrum native cross-chain messaging** for L2 ↔ Orbit chain communication
- **CCIP / LayerZero** for cross-ecosystem (future)

Cross-chain proposals require multisig approval on *each* chain involved. There is no automated cross-chain authority — this is intentional and conservative.

## 8. Failure Modes & Degradation

| Failure | Impact | Mitigation |
|---|---|---|
| Execution Agent down | No new proposals; existing policies still hold | Anyone can run an agent (open source); treasury becomes "read-only" but safe |
| LLM API outage | No natural language → policy compilation | DSL is still usable directly; manual policy submission works |
| Oracle deviation | Proposals rejected by PolicyEngine | Built-in: PolicyEngine checks oracle freshness + deviation |
| Adapter (Aave) compromised | That asset position at risk | Per-adapter circuit breaker; emergency policy disables single adapter |
| Safe multisig captured | Attacker can approve any proposal | Timelock + guardian role; guardian can cancel during timelock |
| PolicyEngine has bug | Catastrophic — wrong proposals approved | Stylus engine is upgradable via timelock + multisig vote of a separate council |
| TreasuryVault has bug | Funds at risk | Treasury contracts are NOT upgradable; migration to v2 vault is opt-in |

## 9. What's Out of Scope (v0.5)

We are explicit about what Helix v0.5 does *not* do:

- ❌ **MEV protection for treasury actions** — assumed to be handled by transaction relayers (Flashbots, MEV Blocker). Future v1.
- ❌ **Privacy / shielded balances** — treasury holdings are public. v2 will integrate Fhenix or similar.
- ❌ **Sub-DAO governance for sub-treasuries** — federation supports delegation but not full sub-governance. v1.
- ❌ **Onchain fiat off-ramp** — TaxEngine produces reports, but does not initiate fiat conversion.
- ❌ **Mobile UI** — desktop dashboard only in v0.5.

## 10. Glossary

| Term | Meaning in Helix |
|---|---|
| **Policy** | A rule set that, given market state and treasury state, produces a deterministic list of recommended actions |
| **Hard constraint** | A predicate that must hold in every post-execution state; cannot be relaxed by policy update |
| **Soft policy** | The active allocation logic; can be updated by treasury owner |
| **Proposal** | A concrete set of actions submitted by the agent, awaiting multisig + timelock |
| **Verdict** | The PolicyEngine's deterministic Approve/Reject decision on a proposal |
| **Action** | A single treasury operation: deposit, withdraw, swap, supply, redeem, etc. |
| **Adapter** | A contract that translates generic Action types into protocol-specific calls |
| **Treasury Owner** | The Safe multisig that controls a Helix treasury |
| **Guardian** | A role (separate from owner) that can cancel proposals during timelock |
