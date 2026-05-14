<div align="center">

# 🧬 Helix

**The Programmable Treasury OS for the Onchain Economy**

*Turn your DAO or onchain business treasury into a policy-driven system. Define rules once. Let agents propose. Multisig executes. Audit forever.*

[![CI](https://github.com/0xCaptain888/helix-treasury/actions/workflows/ci.yml/badge.svg)](https://github.com/0xCaptain888/helix-treasury/actions/workflows/ci.yml)
[![Built on Arbitrum](https://img.shields.io/badge/Built%20on-Arbitrum-12AAFF?style=flat-square)](https://arbitrum.io)
[![Stylus](https://img.shields.io/badge/Core-Stylus%20%2F%20Rust-DEA584?style=flat-square)](https://docs.arbitrum.io/stylus)
[![Robinhood Chain](https://img.shields.io/badge/Robinhood%20Chain-Ready-00C805?style=flat-square)](https://robinhood.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](LICENSE)
[![Open House London](https://img.shields.io/badge/Arbitrum-Open%20House%20London%202026-12AAFF?style=flat-square)](https://arbitrum-london.hackquest.io/)

[Documentation](./docs) · [Architecture](./docs/01-architecture.md) · [Security Model](./docs/05-security-model.md) · [Roadmap](./docs/08-roadmap.md)

</div>

---

## The Problem

Onchain businesses — DAOs, protocols, RWA issuers, payment companies — collectively manage **$50B+ in treasury assets**. They all do it the same way:

> A multisig wallet + a Google Sheet + a treasurer who manually proposes transactions every week.

This breaks at every level. Policy lives in Discord threads, not in code. Rebalancing is reactive, not rules-driven. Tax events are tracked post-hoc. RWA holdings, DeFi positions, and stablecoins live in mental silos. Every action is a multisig fire drill.

**There is no treasury infrastructure native to the programmable economy.** Helix is that infrastructure.

## What Helix Does

Helix turns treasury management into a system where:

1. **Policies are code.** You write rules like *"always keep 18 months of runway in stablecoins; allocate the excess 50% to BENJI, 30% to tokenized SPY, 20% to Aave USDC supply"* — and they become onchain contracts that cannot be ignored or forgotten.

2. **An agent proposes, never executes.** The Helix Execution Agent monitors market conditions, evaluates your policies, and proposes treasury actions. **The agent has zero unilateral power** — every action requires multisig approval.

3. **Every action is provable.** Each treasury operation produces a verifiable audit trail: policy hash, market state at decision time, dry-run simulation results, multisig confirmation, post-execution accounting.

4. **Tax events surface automatically.** Realized gains, dividend distributions, corporate actions on tokenized equities — Helix tags every event with jurisdiction-aware tax metadata, ready for export.

5. **One dashboard, every asset class.** Stablecoins, ARB, tokenized RWAs (Robinhood Chain), DeFi positions (Aave, Pendle), all in one policy-driven view.

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────┐
│                       Treasury Owner (DAO / Org)                │
│                              │                                   │
│              ┌───────────────┴───────────────┐                  │
│              ▼                               ▼                  │
│      ┌──────────────┐                ┌─────────────┐            │
│      │   Helix UI   │                │   Helix     │            │
│      │  (Dashboard) │                │     SDK     │            │
│      └──────┬───────┘                └──────┬──────┘            │
└─────────────┼──────────────────────────────┼───────────────────┘
              │                              │
              │      ┌────────────────────┐  │
              └─────▶│  Execution Agent   │◀─┘
                     │  (off-chain svc)   │
                     │  • monitors        │
                     │  • simulates       │
                     │  • PROPOSES        │
                     └──────────┬─────────┘
                                │ (proposal)
                                ▼
        ╔═══════════════════════════════════════════════════╗
        ║                  ON-CHAIN (Arbitrum)              ║
        ║                                                   ║
        ║   ┌───────────────────────────────────────────┐  ║
        ║   │   PolicyEngine  (Stylus / Rust)           │  ║
        ║   │   • validates proposal against policy     │  ║
        ║   │   • enforces hard constraints             │  ║
        ║   │   • produces verifiable verdict           │  ║
        ║   └───────────────────┬───────────────────────┘  ║
        ║                       │ (if valid)               ║
        ║                       ▼                          ║
        ║   ┌───────────────────────────────────────────┐  ║
        ║   │   TreasuryVault  (Solidity)               │  ║
        ║   │   • multi-asset custody                   │  ║
        ║   │   • timelock + multisig gate              │  ║
        ║   │   • execution after Safe approval         │  ║
        ║   └───────────────────┬───────────────────────┘  ║
        ║                       │                          ║
        ║   ┌──────────┬────────┴────────┬─────────────┐   ║
        ║   ▼          ▼                 ▼             ▼   ║
        ║ Aave V3   Pendle PT     Robinhood RWA     Safe   ║
        ║                                                   ║
        ╚═══════════════════════════════════════════════════╝
```

Full architecture: [docs/01-architecture.md](./docs/01-architecture.md)

## Why This Wins

Helix is built specifically for what the Arbitrum Foundation has publicly stated it wants in 2026:

| Foundation's Stated Direction | How Helix Delivers |
|---|---|
| *"Compliance at the infrastructure layer"* ([blog](https://blog.arbitrum.io/compliance-for-the-programmable-economy/)) | Policies are infrastructure-level smart contracts, not app-level logic |
| *"Rules of a market run in software"* ([blog](https://blog.arbitrum.io/welcome-to-the-programmable-economy/)) | Treasury rules are literal software contracts |
| Institutional adoption as 2026 megatrend | Helix is what makes onchain treasuries operable for institutional actors |
| Robinhood Chain mainnet readiness | Helix is the first treasury layer that natively handles tokenized equities + corporate actions |

**Helix is not a competitor to other Mentorship Cohort 1 projects — it is their customer.** Bond.credit needs a treasury. T3tris managers need treasury reporting. Capa's $150M monthly TPV needs treasury operations. Every Arbitrum-native business is a potential Helix user.

## Key Innovations

1. **Policy DSL with formal hard-constraints** — Policies cannot be configured to violate user-defined inviolable rules (e.g. *"never drop below 6 months runway"*). The Stylus engine enforces this at the bytecode level. See [docs/02-policy-engine.md](./docs/02-policy-engine.md).

2. **Agent-as-proposer, never executor** — Solves the trust gap that has kept AI agents out of serious financial workflows. See [docs/03-execution-agent.md](./docs/03-execution-agent.md).

3. **Verifiable dry-run** — Every proposal includes a simulated end-state. Multisig signers see exactly what will happen before approving.

4. **Tax-aware accounting** — Realized gain/loss, dividends, and corporate actions on tokenized RWAs are auto-tagged at execution time with jurisdiction-specific tax metadata. Industry-first.

5. **Multi-treasury federation** (v0.5) — Sub-treasuries with delegated policy scopes. Useful for DAOs with grants programs, ops budgets, and core treasury under one governance.

## Built On

- **Arbitrum Stylus** — `PolicyEngine` is written in Rust for gas efficiency and verifiable execution semantics
- **Solidity** — `TreasuryVault`, `AssetAdapters`, `TaxEngine`, `ProposalRegistry`
- **Safe (Gnosis)** — Multisig execution layer; Helix is a Safe module
- **Robinhood Chain testnet** — Native tokenized equity support
- **Arbitrum Sepolia** — Primary testnet for cross-chain assets

## Quick Start

```bash
# Clone
git clone https://github.com/0xCaptain888/helix-treasury.git
cd helix-treasury

# Install
pnpm install
foundryup
cargo install --force cargo-stylus

# Test
forge test                                  # Solidity contracts
cd contracts/stylus && cargo stylus check   # Stylus PolicyEngine
pnpm test:agent                             # Execution Agent

# Deploy to Arbitrum Sepolia
cp .env.example .env  # fill in keys
pnpm deploy:sepolia
```

Full setup: [docs/06-deployment.md](./docs/06-deployment.md)

## Deployed Contracts (Arbitrum Sepolia)

| Contract | Address |
|---|---|
| OracleAggregator | [`0x6F4DF8979a8f18Ce3fD2ff941e5a3610E5cAfCa5`](https://sepolia.arbiscan.io/address/0x6F4DF8979a8f18Ce3fD2ff941e5a3610E5cAfCa5) |
| PolicyRegistry | [`0x7058132Ba4aE19983c61590644F2943A3B7fDf80`](https://sepolia.arbiscan.io/address/0x7058132Ba4aE19983c61590644F2943A3B7fDf80) |
| ProposalRegistry | [`0x494960e21058290BB2F1328b6b837dCF26aA5DCb`](https://sepolia.arbiscan.io/address/0x494960e21058290BB2F1328b6b837dCF26aA5DCb) |
| TreasuryVault | [`0x2A46cF6493b377D45908254B0528e38990AA323f`](https://sepolia.arbiscan.io/address/0x2A46cF6493b377D45908254B0528e38990AA323f) |
| TaxEngine | [`0x8a8C3532359aAACb6C3a1060deF4938F6006c8F1`](https://sepolia.arbiscan.io/address/0x8a8C3532359aAACb6C3a1060deF4938F6006c8F1) |
| ERC20Adapter | [`0x77472dADA40B8c30304a7FbbAf14e1b200A5c7FE`](https://sepolia.arbiscan.io/address/0x77472dADA40B8c30304a7FbbAf14e1b200A5c7FE) |
| AaveAdapter | [`0x1D77BBE8E921604c47CAb229Fc0727C5967F19a8`](https://sepolia.arbiscan.io/address/0x1D77BBE8E921604c47CAb229Fc0727C5967F19a8) |
| PendleAdapter | [`0x759aE549389eeDf1F055606fD9b72d071c7Ac3fa`](https://sepolia.arbiscan.io/address/0x759aE549389eeDf1F055606fD9b72d071c7Ac3fa) |
| RobinhoodRWAAdapter | [`0x41d158986CDAd44c7275A681a05215c9Aa1cAe1e`](https://sepolia.arbiscan.io/address/0x41d158986CDAd44c7275A681a05215c9Aa1cAe1e) |

**Mock Tokens (for testnet interaction)**

| Token | Address |
|---|---|
| mUSDC (6 dec) | [`0x9582d2dF303ec2B1fab104A77E249C05571fccC9`](https://sepolia.arbiscan.io/address/0x9582d2dF303ec2B1fab104A77E249C05571fccC9) |
| mWETH (18 dec) | [`0x185346Bd15223740dA8D6D7A11F18b1c93971525`](https://sepolia.arbiscan.io/address/0x185346Bd15223740dA8D6D7A11F18b1c93971525) |
| mARB (18 dec) | [`0xfcc6bE4Dfc45322b8C99fFFB255C1DEcd8f07907`](https://sepolia.arbiscan.io/address/0xfcc6bE4Dfc45322b8C99fFFB255C1DEcd8f07907) |
| mSPY - tokenized equity (18 dec) | [`0x2fc6e0987bF58F5A0Dc76801A9556Ab62bD42049`](https://sepolia.arbiscan.io/address/0x2fc6e0987bF58F5A0Dc76801A9556Ab62bD42049) |
| mTBILL - tokenized T-Bill (18 dec) | [`0x2A7D252D0bFF31eC1098FF642C0934b7124a5A33`](https://sepolia.arbiscan.io/address/0x2A7D252D0bFF31eC1098FF642C0934b7124a5A33) |

**Current Vault Holdings**

| Asset | Balance |
|---|---|
| mUSDC | 340,000 |
| mWETH | 55 |
| mARB | 150,000 |
| mSPY | 700 |
| mTBILL | 150,000 |

> Network: Arbitrum Sepolia (Chain ID 421614). Total on-chain transactions: **94** (14 deployment + 80 interaction suite). Deployer/Safe: `0x2F9fDE6B6FB8d7353aB80F082f85F0d70B809C3b`. Guardian: `0xC7e424c1E4B346c06A35241e7BCa469477483683`. Agent: `0x4c9Cef3bc7F5455d2581b717f115B2c76Fc1d092`.

## Repository Structure

```
helix/
├── README.md                    ← you are here
├── docs/                        ← architecture, security, integration docs
├── contracts/
│   ├── solidity/                ← TreasuryVault, adapters, registry
│   │   ├── adapters/            ← ERC20, Aave, Pendle (PT+YT), RobinhoodRWA
│   │   ├── integrations/        ← HelixSafeModule, SafeProposalAdapter, CorporateActionListener
│   │   └── interfaces/          ← ITreasuryVault, IProposalRegistry, etc.
│   └── stylus/                  ← PolicyEngine (Rust)
├── agent/                       ← Execution Agent (TypeScript/Node)
│   └── src/
│       ├── components/          ← MarketMonitor, PolicyEvaluator, Simulator, ProposalBuilder, Reporter, LLMProvider
│       ├── simulators/          ← AaveSimulator, PendleSimulator, RobinhoodSimulator
│       ├── listeners/           ← CorporateActionWatcher
│       ├── safe/                ← SafeTxBuilder
│       └── cli/                 ← CLI commands (policy:from-nl, agent:tick, agent:status)
├── sdk/                         ← Client SDK for treasury owners
├── scripts/
│   ├── solidity/                ← Foundry deploy scripts (6 phases)
│   └── ts/                      ← verify-deployment.ts
├── policies/                    ← Example HXP policies
└── test/                        ← Integration + invariant tests
```

## Project Status

🟢 **Active development** for [Arbitrum Open House London 2026](https://arbitrum-london.hackquest.io/).

| Milestone | Status | Target |
|---|---|---|
| Architecture & Threat Model (9 named invariants) | ✅ Complete | Week 1 |
| Documentation (8 docs, ~3000 lines) | ✅ Complete | Week 1 |
| Contract interfaces (7 interfaces) | ✅ Complete | Week 1 |
| `HelixTypes.sol` — shared types | ✅ Complete | Week 1 |
| `PolicyEngine` skeleton (Stylus / Rust, 6 files) | ✅ Complete | Week 1 |
| `PolicyRegistry` + 7-day timelock | ✅ Complete | Week 1 |
| `ProposalRegistry` + Safe gate | ✅ Complete | Week 1 |
| `TreasuryVault` (non-upgradable, re-entrancy guard) | ✅ Complete | Week 1 |
| `TaxEngine` — jurisdiction-aware accounting | ✅ Complete | Week 1 |
| `OracleAggregator` (Chainlink + Pyth + deviation guard) | ✅ Complete | Week 1 |
| `TreasuryFactory` — atomic suite deployment | ✅ Complete | Week 1 |
| Asset adapters (Aave v3, Pendle, Robinhood RWA, ERC20) | ✅ Complete | Week 1 |
| `HelixSafeModule` — Safe integration | ✅ Complete | Week 1 |
| Execution Agent (6 components, TypeScript) | ✅ Complete | Week 1 |
| SDK (`@helix-treasury/sdk`) | ✅ Complete | Week 1 |
| Policy examples (DAO, RWA Issuer) | ✅ Complete | Week 1 |
| Foundry deploy scripts (6 phases) | ✅ Complete | Week 1-2 |
| GitHub Actions CI (Forge + Cargo + TS) | ✅ Complete | Week 1 |
| Deploy scripts — constructor params fixed | ✅ Complete | Week 2 |
| `TreasuryVault` PolicyEngine re-validation at execution | ✅ Complete | Week 2 |
| Pyth oracle integration (OracleAggregator) | ✅ Complete | Week 2 |
| CI workflow migrated to pnpm | ✅ Complete | Week 2 |
| SDK ABIs aligned with contracts | ✅ Complete | Week 2 |
| Missing doc-referenced files created (11 files) | ✅ Complete | Week 2 |
| `verify-deployment.ts` script | ✅ Complete | Week 2 |
| Pendle YT support (BUY_YT, SELL_YT, REDEEM_PT_AT_MATURITY) | ✅ Complete | Week 2 |
| LLM subsystem (Anthropic + OpenAI, NL→DSL, explanations) | ✅ Complete | Week 2 |
| Agent components implemented (MarketMonitor, Simulator, ProposalBuilder, Reporter) | ✅ Complete | Week 2 |
| `ProposalRegistry` — 6 core functions (submit, approve, cancel, execute, markExecuted, withdrawBond) | ✅ Complete | Week 2 |
| `PolicyRegistry` — proposeUpdate + activateUpdate with 7-day timelock | ✅ Complete | Week 2 |
| `TaxEngine` — recordExecution, recordCorporateAction, exportPeriod (FIFO/LIFO/HIFO) | ✅ Complete | Week 2 |
| `ERC20Adapter` — execute (TRANSFER, SWAP via Uniswap V3) + simulate | ✅ Complete | Week 2 |
| `AaveAdapter` — execute (SUPPLY, WITHDRAW, BORROW, REPAY) + simulate | ✅ Complete | Week 2 |
| `RobinhoodRWAAdapter` — execute (BUY_RWA, SELL_RWA, REDEEM_RWA) + simulate | ✅ Complete | Week 2 |
| Test files — constructor signatures fixed, all tests compile | ✅ Complete | Week 2 |
| `05_DeployCrossChain.s.sol` — adapter deployment script | ✅ Complete | Week 2 |
| `06_FundTreasury.s.sol` — treasury funding + agent bond script | ✅ Complete | Week 2 |
| Deployment to Arbitrum Sepolia (9 contracts, 14 txns) | ✅ Complete | Week 2 |
| On-chain verification (pause/unpause, bond, breaker, timelock) | ✅ Complete | Week 2 |
| On-chain interaction suite (80 txns: deposits, withdrawals, drills, config) | ✅ Complete | Week 2 |
| Mock token deployment (mUSDC, mWETH, mARB, mSPY, mTBILL) | ✅ Complete | Week 2 |
| PolicyEngine full implementation (Rust) | 🚧 In progress | Week 3 |
| Multi-treasury federation | ⬜ Planned | Week 3 |
| Integration tests + fuzzing invariants | ⬜ Planned | Week 3 |
| Submission | ⬜ | **2026-06-14** |

Mainnet deployment is **explicitly gated** on third-party audit (Trail of Bits / OpenZeppelin) and Immunefi bug bounty launch. Target mainnet: Q3 2026. See [docs/05-security-model.md](./docs/05-security-model.md) for our security posture.

## Documentation

| Doc | Purpose |
|---|---|
| [01-architecture.md](./docs/01-architecture.md) | System architecture, data flow, component boundaries |
| [02-policy-engine.md](./docs/02-policy-engine.md) | Policy DSL grammar, semantics, hard constraints |
| [03-execution-agent.md](./docs/03-execution-agent.md) | Agent decision loop, safety boundaries, prompt design |
| [04-contracts.md](./docs/04-contracts.md) | Contract interfaces, storage layouts, events |
| [05-security-model.md](./docs/05-security-model.md) | Threat model, mitigations, invariants |
| [06-deployment.md](./docs/06-deployment.md) | Step-by-step deployment to testnets |
| [07-integrations.md](./docs/07-integrations.md) | Safe, Aave, Pendle, Robinhood RWA integration |
| [08-roadmap.md](./docs/08-roadmap.md) | v0.1 → v1.0 → v2.0 roadmap |

## Team

**0xCaptain888** -- Solo builder.
Full-stack blockchain engineer. 5+ years Solidity + TypeScript.
Rust / Stylus since 2024. Background in treasury operations for mid-size DAOs.
[@0xCaptain888](https://github.com/0xCaptain888)

*Helix is a solo buildathon entry. The breadth of the codebase -- Stylus PolicyEngine in Rust,
Solidity contracts, TypeScript agent, SDK, full security model -- reflects the depth of the
problem space, not the team size.*

## License

MIT — see [LICENSE](./LICENSE).

---

<div align="center">

**Helix — Treasury as a System, Not a Spreadsheet.**

Built for [Arbitrum Open House London 2026](https://arbitrum-london.hackquest.io/).

</div>
