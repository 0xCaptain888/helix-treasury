# 08 — Roadmap

> Helix is a long-term product. This roadmap is for buildathon judges, future investors, and contributing developers to understand where Helix is going beyond the 3-week submission window.

---

## 1. Vision

> **Helix becomes the default treasury infrastructure for the programmable economy.** Every DAO, every onchain business, every institutional RWA holder uses Helix to express their financial policies as code and to operate their treasury through agent-driven proposals with multisig safety.

In ten years, the question for any onchain organization will not be *"do we have a treasury OS?"* but *"which treasury OS standard are we on?"* Helix aims to be that standard, the way Safe became the default multisig.

## 2. Phased Plan

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│  v0.5 ────▶ v1.0 ────▶ v1.5 ────▶ v2.0 ────▶ v3.0                  │
│  testnet    audited    institutional  privacy  multi-chain          │
│  May–Jun    Q3 2026    Q4 2026     Q1 2027   Q2-Q3 2027            │
│  2026                                                               │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 3. v0.5 — Open House London (current)

**Target: 2026-06-14 submission**

### Goal
Demonstrate that Helix's core thesis works on-chain: policy as code, agent as proposer, multisig as authorizer, multi-asset custody, tax-aware accounting.

### Deliverables

- [x] Architecture, threat model, full docs
- [ ] `PolicyEngine` in Stylus, 8+ built-in functions, 8+ standard hard constraints
- [ ] `TreasuryVault` + `ProposalRegistry` + `PolicyRegistry` + `TaxEngine`
- [ ] Adapters: `ERC20Adapter`, `AaveAdapter`, `PendleAdapter`, `RobinhoodRWAAdapter`
- [ ] Execution Agent (TypeScript) with monitoring/proposing/emergency modes
- [ ] SDK + CLI
- [ ] Deployed on Arbitrum Sepolia + Robinhood Chain testnet
- [ ] One full demo treasury with realistic policy, rebalancing live
- [ ] 50+ property-based tests for PolicyEngine
- [ ] 30+ Foundry invariant tests for vault

### Not in v0.5

- Production audit
- Mainnet
- Privacy features
- Mobile UI
- Sub-treasury full governance
- Federation across non-Arbitrum chains

## 4. v1.0 — Audited Mainnet

**Target: Q3 2026**

### Goal
Helix is production-ready. First real-money treasuries onboard from Arbitrum ecosystem.

### Deliverables

- Third-party audits (Trail of Bits + OpenZeppelin in parallel)
- Immunefi bug bounty live (4-week pre-mainnet, then continuous)
- Mainnet deployment on Arbitrum One
- Mainnet deployment on Robinhood Chain (subject to Robinhood Chain mainnet launch)
- Production-grade RPC infrastructure (multiple providers, automatic failover)
- 3+ design partner treasuries running real funds (target: Arbitrum-ecosystem DAOs)
- Reproducible builds + signed releases
- Public security disclosure policy
- Operational runbook for treasury owners
- 24/7 monitoring for protocol-level invariants

### Success metrics

- $50M+ TVL across treasuries
- 5+ DAO treasuries using Helix for >50% of their AUM management
- Zero critical security incidents

## 5. v1.5 — Institutional Features

**Target: Q4 2026**

### Goal
Make Helix viable for institutional treasury managers (family offices, RIA-style services, corporate treasuries).

### Deliverables

- **Permissioned policy templates** — institutional clients use templates pre-approved by their compliance team
- **Compliance integration**:
  - Sanctions screening as hard constraint (Chainalysis + TRM Labs feeds)
  - Per-jurisdiction tax templates (US, UK, EU/Germany, Singapore, Hong Kong, UAE)
  - Automated tax form generation (1099, K-1, equivalents in other jurisdictions)
- **Audit-grade reporting** — quarterly/annual reports formatted for external auditors (Big 4-compatible)
- **Custodian integration** — hooks for off-chain custody providers (Fireblocks, Anchorage, Copper) where treasuries blend on-chain and off-chain holdings
- **Role-based access control** — treasurer, analyst, viewer roles with different read/write scopes
- **Multi-treasury federation** — parent + sub-treasuries with delegated policy scopes (e.g. DAO core treasury + grants treasury + ops treasury, all managed under one policy hierarchy)
- **Compliance dashboard** — real-time view of which constraints are tightest, which are at risk

### Success metrics

- 2+ institutional treasury managers as paying customers
- 1+ Big 4 auditor signs off on Helix reporting flows
- $200M+ TVL

## 6. v2.0 — Privacy

**Target: Q1 2027**

### Goal
Treasuries should not have to broadcast their holdings to MEV bots and competitors. Privacy is a feature for serious treasury operators.

### Deliverables

- **Fhenix integration** — selected treasury balances are FHE-encrypted; PolicyEngine operates on encrypted state for the encrypted portion
- **Shielded proposal pool** — proposals reveal only the policy hash and aggregate impact, not individual actions, until execution
- **Selective disclosure** — treasury owner can prove to auditor/regulator that a specific constraint was satisfied without revealing balances
- **Zero-knowledge proof of policy compliance** — anyone can verify that a treasury is compliant with its declared hard constraints without seeing the balances

### Why Fhenix specifically

Fhenix is an Arbitrum Open House sponsor and is itself an Arbitrum-native FHE chain. The integration is natural and politically aligned.

### Success metrics

- 1+ enterprise treasury using shielded mode
- Zero leaks of treasury composition pre-execution
- $500M+ TVL

## 7. v3.0 — Multi-Chain Federation

**Target: Q2–Q3 2027**

### Goal
Helix becomes chain-agnostic infrastructure. Treasuries spanning Arbitrum, Robinhood Chain, other Orbit chains, and external L1s/L2s are managed as a single policy-driven entity.

### Deliverables

- **Cross-chain Coordinator** — single off-chain coordinator orchestrates proposals across multiple chains
- **CCIP / LayerZero integration** — for chains outside the Arbitrum ecosystem
- **Cross-chain hard constraints** — e.g. *"total stablecoin runway across all chains ≥ 18 months"*
- **Atomic cross-chain proposals** — proposals span multiple chains with atomic-style guarantees (rollback-on-failure of any leg)
- **Multi-chain tax engine** — unified tax reporting across jurisdictions and chains

### Success metrics

- Treasury managed across ≥3 chains
- Cross-chain atomic actions used in production
- $1B+ TVL

## 8. Long-Term (v4.0+)

Beyond the planned versions, we see several directions:

### Treasury Markets

A marketplace where treasuries express demand for specific instruments (RWA, yield products) and providers compete to supply them. Helix becomes the demand-side substrate.

### Insurance Layer

Insurance pools that underwrite specific Helix policies — *"if this treasury's runway drops below 12 months due to specific covered events (smart contract exploit, oracle manipulation), policyholder is reimbursed."* Premiums priced based on policy hardness.

### Public Pricing Oracles for Policies

Just as Pyth and Chainlink price assets, dedicated oracles price *policy quality* — using on-chain history of Helix treasuries to score policy templates.

### Treasury-as-a-Service for non-crypto orgs

The endgame: a non-crypto corporation manages their corporate cash, payroll, and investments through Helix without knowing it's a blockchain product. Robinhood Chain's tokenized equities make this real because the underlying assets are familiar (real US stocks), not novel crypto primitives.

## 9. What Helix Will Never Be

We are explicit about scope to avoid drift:

- ❌ **Not a hedge fund.** Helix manages *the rules of operation*, not the alpha. Strategy providers can plug in via custom policies, but Helix itself takes no view on markets.
- ❌ **Not a brokerage.** Helix does not custody assets directly; the TreasuryVault holds them, but Helix the entity is not a financial institution.
- ❌ **Not a wallet UX.** The dashboard is functional, not consumer-grade. Helix is for serious treasury operators, not retail.
- ❌ **Not a chain.** Helix is application infrastructure. We deploy on Arbitrum, Robinhood Chain, and other Orbit chains; we are not building our own chain.

## 10. Funding & Sustainability

The path:

- **Buildathon (Open House London)**: Win, validate thesis, get into Mentorship Program
- **Mentorship Program** (Q3 2026, if selected): Refine product, develop go-to-market, prepare for fundraising
- **Seed round** (Q4 2026 / Q1 2027): Fund audit, scale design partners. Likely investors: Pantera, Electric Capital, Tandem, ecosystem-aligned funds.
- **Series A** (2027): Scale revenue. Helix revenue model: **subscription per treasury** (tiered by AUM) + **transaction fee on agent-mediated actions** (basis points on action value, capped). No token planned for v0.5–v2.0.

### Why no token (initial)

A token launched early would distract from the product. The product is *infrastructure*. Adoption looks like: 100 DAOs paying subscriptions because Helix saves them treasurer time and reduces ops risk. Tokenization, if appropriate, comes after product-market fit is unmistakable.

## 11. Team Trajectory

(For the buildathon team, this section is to be filled in by you. Suggested structure):

| Phase | Team size | Roles needed |
|---|---|---|
| v0.5 buildathon | 1–3 | Founder, builder(s) |
| v1.0 mainnet | 5–8 | + Smart contract engineer, security engineer, designer, BD lead |
| v1.5 institutional | 15–20 | + Sales, customer success, additional engineers |
| v2.0 privacy | 25–35 | + Cryptography lead, compliance lead, regional sales |

## 12. Concluding Note

We are aware this roadmap is ambitious. It is also necessary. The programmable economy will have a treasury OS — the question is whether it is built by a single deliberate team with a coherent vision, or assembled piecemeal by every protocol independently. Helix is our bet on the first path.

For the buildathon: we are not asking judges to believe v3.0 will happen. We are asking them to evaluate whether **v0.5 demonstrates the core thesis**, and whether the **plan to get from v0.5 to v1.0 is credible**. Everything beyond v1.0 is upside.
