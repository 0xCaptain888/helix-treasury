# 05 — Security Model & Threat Model

> Most hackathon projects skip this document. Helix doesn't, because Helix is treasury infrastructure: a single exploitable assumption is the difference between a $1M product and a $0 product. This document enumerates what we trust, what we don't, what can go wrong, and what stops it.

---

## 1. Asset Classification

We classify everything Helix touches:

| Asset class | Examples | Loss tolerance |
|---|---|---|
| **Tier 0: Treasury funds** | USDC, ARB, BENJI, tokenized equities, LP positions | Zero. Any loss is a critical incident. |
| **Tier 1: Agent bonds** | Slashing collateral posted by agents | Low. Slashing is expected behavior, but never to attacker. |
| **Tier 2: Operational data** | Tax records, audit trails, proposal history | Low. Must be reconstructible from on-chain events. |
| **Tier 3: Convenience features** | LLM-generated explanations, dashboard cache | High. Failures degrade UX, not safety. |

## 2. Trust Boundaries (Explicit)

Helix's trust assumptions, in plain language:

### We trust:
- **Arbitrum L2** to provide finality and fraud proofs. Compromising Arbitrum compromises Helix; we accept this and inherit Arbitrum's security model.
- **Safe (Gnosis)** multisig contracts. Battle-tested with billions in TVL.
- **Chainlink + Pyth oracles** for price feeds, with deviation guards on top.
- **Treasury owners** to honestly set policies. Helix prevents *accidental* loss, not *intentional* self-harm by the owner.

### We do not trust:
- **The Execution Agent.** It has no privileged role. Compromise = liveness loss, not safety loss.
- **LLMs.** Hallucination is assumed. LLM outputs are human-reviewed before any on-chain effect.
- **Adapter protocols.** Aave, Pendle, RWA issuers are treated as untrusted external systems. Circuit breakers per adapter.
- **RPC providers.** Multiple endpoints with cross-validation.
- **Off-chain notifications.** Discord/Slack outage cannot delay on-chain safety actions.

## 3. Threat Model (STRIDE)

We use STRIDE to enumerate threats systematically.

### Spoofing

| Threat | Mitigation |
|---|---|
| Attacker submits a proposal pretending to be the authorized agent | `submitProposal()` requires `msg.sender ∈ authorizedAgents` AND agent signature; double-checked |
| Attacker spoofs Safe multisig approval | Safe approval signatures verified on-chain by ProposalRegistry; cannot be forged |
| Attacker spoofs oracle data | OracleAggregator requires `minSources` independent feeds |

### Tampering

| Threat | Mitigation |
|---|---|
| Attacker modifies proposal between submission and execution | Proposals are immutable once submitted; `proposalId = keccak256(content)` |
| Attacker modifies policy bytecode after activation | Bytecode is content-addressable; activated hash cannot be changed |
| Attacker modifies treasury state during execution to bypass post-condition checks | Re-evaluation at execution time uses fresh state read |
| Attacker manipulates oracle within deviation tolerance | Hard constraints are designed to be robust to oracle noise; manipulation insufficient for profitable extraction |

### Repudiation

| Threat | Mitigation |
|---|---|
| Treasury owner denies they approved a proposal | All approvals are on-chain Safe events; non-repudiable |
| Agent denies submitting a malicious proposal | Agent signatures are stored; agent identity is on-chain |

### Information Disclosure

| Threat | Mitigation |
|---|---|
| Attacker reads treasury balances | All on-chain treasury data is public. Not a Helix concern (privacy is a v2 feature with Fhenix integration). |
| Attacker reads pending proposals to front-run | Mitigated by use of private transaction pools (Flashbots, MEV Blocker) for treasury actions; v0.5 documents the integration |
| Attacker reads LLM prompts | LLM prompts contain non-secret policy text; no PII or keys |

### Denial of Service

| Threat | Mitigation |
|---|---|
| Attacker spams proposals to exhaust agent bond | Bond slashed only on rejection-with-malformed; legitimate-but-rejected proposals are free |
| Attacker triggers oracle to revert, freezing treasury | Treasury can still receive deposits; only state-changing actions are blocked, which is the desired behavior |
| Attacker exploits PolicyEngine gas to make evaluation prohibitively expensive | Compile-time gas bounds via PolicyVerifier; rejection if proposal would exceed bound |
| Attacker DOS the off-chain agent | Agent is replaceable; treasury degrades to read-only safety |

### Elevation of Privilege

| Threat | Mitigation |
|---|---|
| Agent escalates to executor | Architecturally impossible: agent has no `execute` path |
| Safe signer escalates to bypass timelock | Timelock is enforced in ProposalRegistry; signers can `approve` but not `execute` instantly |
| Adapter escalates to drain vault | Adapters are called only by vault with strict-typed actions; adapter cannot call back into vault except via well-defined re-entrancy-guarded paths |
| Anyone escalates to update policy | Policy update requires Safe approval + 7-day timelock + verifier pass |

## 4. Specific Attack Scenarios

### 4.1 Compromised Agent

**Scenario:** Attacker gains full control of agent server (RCE) and private key.

**What attacker can do:**
- Submit any proposal they want
- Read all treasury data (already public)
- Stop submitting valid proposals (deny rebalancing)

**What attacker cannot do:**
- Make any proposal execute. Every proposal must:
  1. Pass on-chain PolicyEngine (rejects everything not matching policy)
  2. Pass multisig approval
  3. Pass 24-hour timelock
  4. Pass re-evaluation at execution time
- Modify policies (Safe-controlled)
- Steal bond (it's locked in ProposalRegistry; rotates with agent key rotation)

**Recovery:** Multisig calls `setAuthorizedAgent(newAgentAddr)`. Old agent's bond is unaffected and remains slashable for past malformed proposals.

### 4.2 Compromised Safe Multisig Signer

**Scenario:** One Safe signer's key is stolen.

**What attacker can do:**
- Reach signer's approval count but not threshold (assuming multisig is non-1)
- Trigger normal Safe key-recovery flow

**What attacker cannot do:**
- Approve a proposal alone (threshold not met)
- Modify policy alone
- Pause emergency mode alone

**Recovery:** Safe key rotation, standard Safe procedure.

### 4.3 Compromised Multisig Threshold (`M-of-N` reached)

**Scenario:** Attacker captures enough Safe signers to approve proposals.

**What attacker can do:**
- Approve any agent-submitted proposal
- Propose a policy update (with attacker's preferred policy)
- Wait 7 days for policy update to activate; meanwhile approve drain proposals

**What stops them:**
- Each approved proposal must still pass PolicyEngine against the *current* policy
- Current policy's hard constraints (e.g. `RUNWAY_FLOOR`, `MAX_DAILY_MOVEMENT`) block large drains
- 24-hour execution timelock gives community time to act
- **Guardian role** can `cancelProposal` during timelock — guardian is a separate multisig that is harder to compromise
- 7-day policy-update timelock gives community time to respond to malicious policy
- **Hard constraints can only be tightened, never relaxed** — even a fully-captured multisig cannot remove `RUNWAY_FLOOR`

This is the deepest safety property of Helix: a captured multisig cannot turn the system into a draining machine in one transaction.

### 4.4 Oracle Manipulation

**Scenario:** Attacker manipulates underlying CEX prices to skew oracle output.

**Mitigations:**
1. OracleAggregator requires ≥2 independent sources within deviation tolerance
2. PolicyEngine uses time-weighted averages (1-hour TWAP) for allocation decisions
3. Hard constraints expressed in unit values that are robust to short-term price swings (e.g. `RUNWAY_FLOOR` is in months, not USD count)
4. Execution-time re-evaluation: if oracle has moved abnormally between proposal and execution, the proposal is rejected

### 4.5 Adapter Exploit

**Scenario:** Aave V3 has a critical bug; attacker drains it.

**What this means for Helix:**
- Treasury's `aUSDC` positions may be partially or fully lost
- Helix's other positions are unaffected

**Pre-event mitigations:**
- `MAX_PROTOCOL_EXPOSURE` hard constraint limits Aave exposure to e.g. 30% of NAV
- Per-adapter circuit breakers detect anomalous returns and freeze further actions to that adapter
- Forta integration triggers `emergencyMode` (agent shifts to redeem-only proposals)

**Recovery:**
- `EMERGENCY_REDEEM` proposals can be approved quickly
- Multisig may approve a one-time policy update via fast-track (24h timelock) to remove the compromised adapter

### 4.6 Front-running Treasury Actions

**Scenario:** Mempool watcher front-runs a large SWAP.

**Mitigation:**
- Treasury actions are routed through MEV protection (Flashbots Protect, MEV Blocker)
- v0.5 ships with Flashbots Protect integration on Arbitrum
- For very large actions, use TWAP execution (split over multiple blocks) — supported by `SwapAdapter` parameters

### 4.7 Reorg Attacks

**Scenario:** L1 reorg on settlement causes Arbitrum state to change.

**Mitigation:**
- Helix actions are subject to Arbitrum's finality guarantees
- For very-large actions, we add a finality delay parameter to relevant adapters: actions wait `N` confirmation blocks before considered final for tax purposes

## 5. Invariants

These are the properties Helix promises will *always* hold, regardless of any input. We test them with property-based tests (`proptest` for Stylus, Foundry invariants for Solidity).

### Liquidity invariants
- **I1:** `TreasuryVault.totalValue >= sum(adapter.simulate(state).value)` — accounting always sums correctly
- **I2:** After any state transition: `hard_constraints(new_state) ⊆ hard_constraints(old_state)` — constraints can only be tightened

### Authorization invariants
- **I3:** No function on `TreasuryVault` that modifies fund state can be called without a corresponding `Approved` proposal in `ProposalRegistry` (except `deposit`, which only adds)
- **I4:** `ProposalRegistry.executeProposal` always calls `PolicyEngine.evaluate` on entry; mismatches revert

### Policy invariants
- **I5:** A `Proposal` is in state `Approved` iff `PolicyEngine.evaluate(...)` returned `Approve` AND multisig has approved
- **I6:** `activePolicyHash` always refers to a policy that has passed verifier and timelock

### Liveness invariants
- **I7:** Treasury can always receive deposits (no auth needed)
- **I8:** Safe can always approve a `EMERGENCY_REDEEM` proposal without timelock (fast-path)
- **I9:** Guardian can always cancel a pending proposal during its timelock window

## 6. Audit & Bug Bounty Path

### Pre-mainnet audit (mandatory)

We will engage two firms in parallel for the v1.0 release:

- **Trail of Bits** — focus on PolicyEngine (Stylus / Rust)
- **OpenZeppelin** — focus on TreasuryVault, ProposalRegistry, adapters

Audit reports will be published before mainnet, including all findings and resolutions.

### Bug Bounty

After audit completion:

| Severity | Bounty (Helix v1) |
|---|---|
| Critical (funds at risk) | up to $100,000 |
| High (unauthorized actions) | up to $25,000 |
| Medium (DoS, policy bypass without funds) | up to $5,000 |
| Low (gas griefing, minor) | up to $1,000 |

Hosted on Immunefi.

### Testnet bounty (now)

Even on testnet, we offer a small bounty for protocol-level findings:

- Critical: $1,000 + acknowledgment
- High: $500
- Medium: $250

Report to `security@helix-treasury.xyz` (TBD post-buildathon).

## 7. Operational Security

### Agent operator checklist

If you run a Helix agent (whether for your own treasury or as a service):

- [ ] Agent private key stored in HSM/KMS (AWS KMS, GCP KMS, HashiCorp Vault); never in `.env`
- [ ] RPC endpoint uses authenticated provider; fallback configured
- [ ] LLM API key in separate KMS namespace from agent signing key
- [ ] Agent runs on hardened host; container with read-only filesystem
- [ ] Outbound network restricted to: RPC, LLM provider, oracle API, notification webhooks
- [ ] Audit logs shipped to immutable storage (S3 with object lock)
- [ ] Periodic key rotation (quarterly recommended)

### Treasury owner checklist

If you operate a Helix treasury:

- [ ] Safe threshold ≥ 3/5 (recommended)
- [ ] Guardian multisig with different signers than the main Safe
- [ ] Hard constraints set conservatively at creation; review every 90 days
- [ ] Drill: practice an `EMERGENCY_REDEEM` proposal at deployment time
- [ ] Subscribe to security@helix-treasury.xyz announcements list
- [ ] Set up Forta subscriptions for your adapters

## 8. What "v0.5 on testnet" means for security

We are explicit about what is NOT yet true in v0.5:

- ❌ Not yet third-party audited
- ❌ Not yet on Immunefi
- ❌ Not yet recommended for production funds

We are explicit about what IS true:

- ✅ Property-based testing for PolicyEngine
- ✅ Foundry invariant tests for vault flows
- ✅ Architecture and threat model reviewed in this document
- ✅ Open source from day one
- ✅ Reproducible builds for agent

## 9. Disclosure Policy

If you find a vulnerability:

1. **Do not exploit it.** Even on testnet, even for "research."
2. Email `security@helix-treasury.xyz` with details. Use our PGP key (TBD).
3. We acknowledge within 48 hours.
4. We coordinate disclosure within 90 days (or sooner if mitigation is fast).
5. Public disclosure includes credit to you (unless you prefer anonymity).

## 10. Final Note

> **Treasury infrastructure is a category where being right matters more than being fast.**
>
> If a bridge has a bug, users lose their bridge transaction. If Aave has a bug, depositors lose their position. If a treasury OS has a bug, an entire organization's runway is at risk. The blast radius is the highest of any product type we know.
>
> Helix is built with that responsibility in mind. We will not ship to mainnet until we are confident. We document everything, including what we do not yet know. We invite scrutiny.
