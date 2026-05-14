# 03 — Execution Agent

> The Execution Agent is the off-chain brain of Helix. It monitors, simulates, and **proposes** treasury actions. It does not, and cannot, move funds.

## 1. Design Philosophy

The Helix agent is built on a single, blunt principle:

> **An agent that can lose money is an agent that has too much power.**

Every design decision flows from this. The agent's signing key cannot send transactions that move treasury funds. The agent's RPC endpoints to the TreasuryVault are read-only. The only state-changing call the agent makes on-chain is `ProposalRegistry.submitProposal()` — which is a candidate, not an authorization.

This is the architecture that makes AI agents safe for serious money. It is also what differentiates Helix from "AI trading bot" projects that share neither the safety properties nor the long-term legitimacy.

## 2. Agent Lifecycle

```
                  ┌──────────────────────────────────────────┐
                  │            AGENT INSTANCE                │
                  │  ─────────────────────────────────────   │
                  │                                          │
   tick timer ───▶│  ┌─────────────────────────────────┐    │
                  │  │  1. Observe                      │    │
   block event ──▶│  │     • read treasury state        │    │
                  │  │     • read oracle snapshot       │    │
   manual req ───▶│  │     • read active policies       │    │
                  │  └────────────┬────────────────────┘    │
                  │               ▼                          │
                  │  ┌─────────────────────────────────┐    │
                  │  │  2. Evaluate                     │    │
                  │  │     • for each policy, check     │    │
                  │  │       trigger condition          │    │
                  │  │     • compute target actions     │    │
                  │  └────────────┬────────────────────┘    │
                  │               ▼                          │
                  │  ┌─────────────────────────────────┐    │
                  │  │  3. Simulate                     │    │
                  │  │     • run actions against        │    │
                  │  │       state in a forked sim      │    │
                  │  │     • check post-state vs        │    │
                  │  │       hard constraints           │    │
                  │  │     • if fail → re-plan or skip  │    │
                  │  └────────────┬────────────────────┘    │
                  │               ▼                          │
                  │  ┌─────────────────────────────────┐    │
                  │  │  4. Propose                      │    │
                  │  │     • build Proposal struct      │    │
                  │  │     • sign with agent key        │    │
                  │  │     • submit on-chain            │    │
                  │  │     • notify off-chain channels  │    │
                  │  └────────────┬────────────────────┘    │
                  │               ▼                          │
                  │  ┌─────────────────────────────────┐    │
                  │  │  5. Track                        │    │
                  │  │     • watch for verdict event    │    │
                  │  │     • watch for multisig action  │    │
                  │  │     • watch for execution        │    │
                  │  │     • record outcome             │    │
                  │  └─────────────────────────────────┘    │
                  │                                          │
                  └──────────────────────────────────────────┘
```

## 3. Components

The agent is built as a set of single-responsibility services. We deliberately *do not* use a generic LLM-orchestration framework (LangChain, CrewAI, AutoGen) for the core decision loop. Those frameworks hide control flow inside prompts. Treasury operations require auditable, reproducible control flow. We use LLMs *only* in the natural-language → DSL compilation step, which is human-reviewed before commitment.

### 3.1 Market Monitor

Watches:
- Treasury vault events (`Deposit`, `Withdraw`, `ProposalExecuted`)
- Oracle price feeds (Chainlink, Pyth on Arbitrum)
- Yield rates (Aave reserve rates, Pendle PT yields)
- Robinhood Chain corporate-action announcements (via testnet event stream)
- Block timer (default 4-hour cadence)

On each event of interest, enqueues a `Tick` for the policy evaluator.

### 3.2 Policy Evaluator

Replicates the on-chain PolicyEngine logic in TypeScript. This is **kept in sync** with the Stylus implementation via a shared test corpus (`test/policy-corpus/`) that runs against both implementations and asserts identical outputs.

```typescript
class PolicyEvaluator {
  evaluate(state: TreasuryState, market: MarketState, policy: Policy):
      | { kind: "no-trigger" }
      | { kind: "trigger", actions: Action[], rationale: string }
      | { kind: "violation", reason: string }
  { ... }
}
```

### 3.3 Simulator

Given a candidate action set, the simulator runs them against a forked-state view to produce a predicted post-state.

For on-chain actions, we use `eth_call` with state overrides to simulate against the actual contracts. For protocol-specific behavior (Aave supply, Pendle swap), we either:
- Call the protocol's view function in simulation mode (e.g. `Pool.getReserveData`)
- Replay the protocol contract logic locally (for cases where view functions are insufficient)

The simulator output is hashed and committed to in the `Proposal`. The on-chain executor re-runs the same simulation; mismatches abort execution.

### 3.4 Proposal Builder

Assembles a `Proposal`:

```typescript
function buildProposal(
  triggered_policy: Policy,
  actions: Action[],
  market: MarketState,
  sim_result: SimulationResult,
): Proposal {
  return {
    policyHash: keccak256(triggered_policy.bytecode),
    marketStateHash: market.commit(),
    actions: actions,
    dryRunResultHash: keccak256(sim_result.serialize()),
    expiresAt: now() + PROPOSAL_TTL,
    agentSignature: agentKey.sign(...),
  };
}
```

### 3.5 LLM Subsystem (Natural Language Interface)

Used **only** for:

1. **Natural language → DSL translation.** Treasury owner writes *"keep 18 months runway, invest excess 50/30/20 in BENJI/SPY/Aave."* Agent uses LLM to produce a draft `.hxp` policy. **The owner reviews the DSL before committing.** LLM output is never directly committed.

2. **Proposal explanation.** When a proposal is submitted, the agent generates a human-readable justification for the multisig signers: *"Triggered by policy `runway-rebalance` because current runway exceeds 24 months. This proposal supplies 1.85M USDC to Aave, swaps 1.8M USDC → BENJI, swaps 1.35M USDC → SPY_TOKEN. Post-execution runway = 18 months."*

3. **Anomaly summarization.** If a proposal is rejected by the PolicyEngine, the agent uses an LLM to translate the technical rejection reason into actionable feedback.

LLMs are **never** in the path of:
- Deciding *which* actions to take (that's the deterministic policy code)
- Signing transactions
- Setting parameters
- Bypassing constraints

### 3.6 Reporter

Subscribes to on-chain events and pushes them to configured channels:
- Discord webhook (proposal submitted, approved, executed)
- Slack
- Email digest (daily / weekly)
- Tax report (monthly)

## 4. Tick Algorithm (Reference Implementation)

```typescript
async function tick(treasury: Address): Promise<void> {
  const state    = await vault.getState();
  const market   = await oracle.snapshot();
  const policies = await registry.getActivePolicies(treasury);

  for (const policy of policies) {
    if (!policy.trigger.evaluate(state, market)) continue;

    const plan = policy.compute(state, market);
    if (plan.actions.length === 0) continue;

    // Run hard constraints in simulation
    const sim = await simulator.run(state, plan.actions, market);
    const violations = policy.hardConstraints
      .map(c => c.check(sim.postState))
      .filter(v => !v.ok);

    if (violations.length > 0) {
      // Try to re-plan with constraint awareness
      const repaired = policy.repair(state, market, violations);
      if (repaired === null) {
        await reporter.skip(treasury, policy, violations);
        continue;
      }
      plan.actions = repaired.actions;
      sim = await simulator.run(state, plan.actions, market);
    }

    const proposal = builder.build(policy, plan, market, sim);
    const txHash = await registry.submitProposal(proposal);
    await reporter.proposed(treasury, proposal, txHash);
  }
}
```

## 5. Security Boundaries (Negative Space)

The Helix Agent **cannot**:

| Action | Why it can't |
|---|---|
| Move funds from TreasuryVault | TreasuryVault rejects calls from any address except the ProposalRegistry, and only with a verdict-approved proposal |
| Approve its own proposals | Multisig approval comes from Safe signers, not the agent |
| Bypass timelock | Timelock is enforced by ProposalRegistry; agent has no role |
| Modify policies | Policies require Safe + 7-day timelock |
| Update its own code unilaterally | Agent runtime is open-source; treasury owners run their own instance |
| Use private keys to authorize anything except `submitProposal()` | Agent's only on-chain role is proposing |

If the agent is fully compromised — its private key stolen, its server taken over — the worst the attacker can do is:
- Spam invalid proposals (rejected by PolicyEngine, cost-bounded by minimum proposal stake)
- Stop generating proposals (treasury becomes read-only)

The attacker cannot move funds. The attacker cannot weaken policies. The attacker cannot bypass multisig.

## 6. Failure Modes

| Failure | Behavior | Recovery |
|---|---|---|
| Agent process crashes | No new proposals; existing approved proposals still executable by anyone | Restart |
| Agent's RPC provider down | Tick skipped; logged | Failover to backup RPC |
| LLM API down | NL → DSL unavailable; DSL editing still works | None needed |
| Stale oracle | PolicyEngine rejects proposal (oracle freshness check) | Wait for oracle update |
| Agent private key compromised | Attacker can spam proposals; cannot move funds | Rotate agent key via `ProposalRegistry.setAuthorizedAgent()` (multisig action) |
| Agent submits malformed proposal | PolicyEngine rejects; event emitted | None needed; logs surface bug |

## 7. Operational Modes

The agent has three operational modes, set per-treasury:

### MONITORING (default for new treasuries)
- Agent observes, computes proposals, but does **not** submit on-chain
- Proposals are surfaced in Helix UI as "draft proposals" for owner review
- Useful for first 30 days to build owner confidence

### PROPOSING (steady state)
- Agent submits proposals on-chain automatically
- Multisig review and timelock still in place
- Default after monitoring period

### EMERGENCY
- Agent submits *only* `EMERGENCY_REDEEM` proposals — actions that reduce risk without rebalancing
- Triggered by: oracle deviation > 10%, protocol exploit detection (via Forta integration), treasury owner toggling `emergencyMode`
- Useful during market stress

## 8. Self-Custody of the Agent

Each treasury owner runs their own agent instance. We provide:

1. **Docker image** with deterministic build (image hash published)
2. **Helm chart** for Kubernetes deployments
3. **Hosted option** for treasuries that prefer it (paid tier, not in v0.5)

Configuration is via `config.yaml`:

```yaml
treasury:
  vault_address: "0x..."
  policy_registry: "0x..."
  proposal_registry: "0x..."
chain:
  primary: arbitrum-sepolia
  rpc_urls: [...]
  fallback_rpc: [...]
agent:
  key_source: env  # or aws-kms, gcp-kms, hashicorp-vault
  tick_interval: 4h
  modes: [proposing]
llm:
  provider: anthropic  # or openai
  model: claude-sonnet
  enabled_features: [proposal_explanation, nl_to_dsl]
oracles:
  primary: chainlink
  secondary: pyth
  max_staleness: 30m
reporting:
  discord_webhook: "..."
  email: "..."
```

## 9. Agent Identity & Reputation (v0.5+)

Each agent has an on-chain identity (ERC-8004 compatible) that tracks:

- Total proposals submitted
- Proposals approved by multisig (% rate)
- Proposals rejected by PolicyEngine (% rate)
- Average time-to-execution

This provides a reputation surface useful for:

- Treasury owners comparing agent implementations
- Future "shared agent" deployments where a single agent runtime serves many treasuries
- Insurance markets (v1) pricing agent reliability

## 10. Why Not Just Use Existing Frameworks?

We considered and rejected:

**LangChain / CrewAI / AutoGen** — These hide control flow inside prompts. Our control flow needs to be auditable: every transition must have an explicit cause, every decision must be reproducible. We cannot debug a treasury rejection through a prompt-engineering issue.

**ElizaOS / Virtuals** — Optimized for character agents and social interaction. Wrong problem domain.

**Self-built (our choice)** — A few hundred lines of explicit TypeScript orchestrating well-defined services. Slow to extend, but every decision is in code, not in a prompt.

LLMs remain useful at the edges (NL→DSL, explanation). They are not allowed at the core.

## 11. Testing the Agent

Three test suites:

1. **Replay tests.** A corpus of historical state-market pairs with expected proposal outputs. CI runs the agent against the corpus; deviation fails the build.

2. **Differential tests vs Stylus.** Same inputs run against both the TS evaluator and the Stylus PolicyEngine; outputs must match.

3. **Chaos tests.** Inject failures (RPC drops, oracle stale, LLM errors) and assert the agent fails-closed (no spurious proposals).

## 12. Observability

Every tick produces a structured log:

```json
{
  "ts": "2026-06-01T12:00:00Z",
  "treasury": "0x...",
  "tick_id": "uuid",
  "state_snapshot_hash": "0x...",
  "policies_evaluated": 3,
  "proposals_submitted": 1,
  "proposal_ids": ["0x..."],
  "skipped": [
    { "policy": "rebalance", "reason": "drift below threshold" }
  ],
  "duration_ms": 482
}
```

Logs are exported to OpenTelemetry; we ship dashboards for Grafana.
