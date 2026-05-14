# 02 — Policy Engine & DSL

> The PolicyEngine is the single most important contract in Helix. This document is the canonical specification of the Policy DSL, its semantics, and the hard-constraint system.

## 1. What is a Policy?

A **Policy** is a deterministic function:

```
policy: (TreasuryState, MarketState) → List<Action>
```

Given the current treasury holdings and a snapshot of market conditions, a policy produces a list of recommended treasury operations. The same inputs always produce the same outputs — there is no randomness, no off-chain calls, no time-dependence except via explicit time inputs.

A policy is paired with a set of **hard constraints** — predicates that must hold in every post-execution state. Hard constraints are immutable for the lifetime of a treasury.

```
HardConstraint: TreasuryState → Boolean

A proposal is valid iff:
   ∀ c ∈ hard_constraints, c(post_state) = true
   AND
   policy(pre_state, market) ≈ proposal.actions
```

## 2. Anatomy of a Policy Document

A policy is declared in **HXP** (Helix Policy) format — a structured, human-readable DSL that compiles to a deterministic on-chain representation.

```hxp
policy "core-treasury-v1" {
    version: 1
    owner: 0xSafeAddressOfDAO
    chain: arbitrum-one

    # ─── HARD CONSTRAINTS (immutable) ─────────────
    hard_constraint runway_floor {
        require: months_of_runway(state, monthly_burn = 250000 USDC) >= 6
        on_violation: reject
    }

    hard_constraint single_asset_cap {
        require: max_share(state, exclude = [USDC, USDT]) <= 0.40
        on_violation: reject
    }

    hard_constraint daily_movement_cap {
        require: total_movement_24h(state) <= 0.10 * total_value(state)
        on_violation: reject
    }

    # ─── SOFT POLICY (updatable) ──────────────────
    allocation {
        when: months_of_runway(state, monthly_burn = 250000 USDC) > 18

        target: {
            USDC: keep(18 months runway)
            BENJI: 0.50 of excess
            SPY_TOKEN: 0.30 of excess     # on Robinhood Chain
            AAVE_USDC_SUPPLY: 0.20 of excess
        }

        rebalance_when: drift > 0.05
        max_rebalance_per_week: 1
    }

    # ─── REPORTING ─────────────────────────────────
    report {
        tax_jurisdiction: US
        report_cadence: monthly
        tax_lots: HIFO        # Highest-In-First-Out
    }

    # ─── GOVERNANCE ────────────────────────────────
    governance {
        proposer: helix_agent
        approver: safe(0xSafeAddressOfDAO)
        timelock: 24 hours
        guardian: 0xGuardianMultisig
    }
}
```

## 3. DSL Grammar (BNF, simplified)

```
policy_doc      ::= "policy" STRING "{" policy_body "}"
policy_body     ::= meta_decl* hard_constraint* soft_policy report? governance

meta_decl       ::= "version:" INTEGER
                  | "owner:" ADDRESS
                  | "chain:" CHAIN_ID

hard_constraint ::= "hard_constraint" IDENT "{"
                       "require:" expr
                       "on_violation:" violation_action
                    "}"

violation_action ::= "reject" | "cancel_proposal" | "freeze_treasury"

soft_policy     ::= "allocation" "{"
                       "when:" expr
                       "target:" "{" target_entry* "}"
                       ( "rebalance_when:" expr )?
                       ( "max_rebalance_per_week:" INTEGER )?
                    "}"

target_entry    ::= ASSET ":" target_spec
target_spec     ::= "keep(" expr ")"
                  | NUMBER "of" "excess"
                  | NUMBER "of" "total"
                  | "remainder"

expr            ::= literal
                  | builtin_call
                  | expr binop expr
                  | "(" expr ")"

builtin_call    ::= IDENT "(" arg_list ")"

# Built-in functions are listed in §5.
```

## 4. Type System

The DSL has six primitive types and one composite:

| Type | Examples | Semantics |
|---|---|---|
| `AmountUSDC` | `250000 USDC`, `1.5 SPY` | Fixed-point with asset tag |
| `Ratio` | `0.50`, `40%` | `[0, 1]` rational; emitted as 18-decimal fixed-point |
| `Duration` | `18 months`, `24 hours` | Compiled to seconds (uint256) |
| `Address` | `0xabc...` | EVM address |
| `Asset` | `USDC`, `BENJI`, `SPY_TOKEN` | Token symbol resolved via AssetRegistry |
| `Bool` | `true`, `false` | |
| `Set<T>` | `[USDC, USDT]` | Ordered collection |

The compiler rejects type errors at compile time (e.g. comparing `AmountUSDC` to `Ratio`).

## 5. Built-in Functions

All built-ins are **pure** — they read state but never mutate it. They are evaluated on-chain by the PolicyEngine in Stylus, with identical implementations available in the agent's TypeScript simulator for dry-run.

### State accessors

| Function | Returns | Description |
|---|---|---|
| `total_value(state)` | `AmountUSDC` | Treasury total NAV in USDC, oracle-priced |
| `balance(state, asset)` | `AmountUSDC` | Balance of a specific asset, USDC-denominated |
| `share(state, asset)` | `Ratio` | Asset's share of total NAV |
| `max_share(state, exclude=[...])` | `Ratio` | Largest asset share, excluding listed assets |
| `months_of_runway(state, monthly_burn)` | `Ratio` | Stablecoin balance / monthly burn |
| `total_movement_24h(state)` | `AmountUSDC` | Sum of executed action sizes in last 24h |

### Market accessors

| Function | Returns | Description |
|---|---|---|
| `price(market, asset)` | `AmountUSDC` | Oracle median price; reverts if stale > MAX_STALENESS |
| `apy(market, source)` | `Ratio` | Annualized yield, e.g. `apy(market, AAVE_USDC)` |
| `volatility_30d(market, asset)` | `Ratio` | Realized 30-day volatility |

### Time accessors

| Function | Returns | Description |
|---|---|---|
| `now()` | `uint256` | Block timestamp |
| `last_rebalance(state, scope)` | `uint256` | Timestamp of last rebalance action |
| `since(t)` | `Duration` | `now() - t` |

### Operators

```
+ - * /   on Amount, Ratio
> < >= <= == !=   numeric/duration
&& || !   boolean
in   set membership
```

## 6. Compilation

Policy compilation is a multi-stage pipeline:

```
.hxp source
   │
   │   parse
   ▼
AST (abstract syntax tree)
   │
   │   type check + name resolution
   ▼
Typed AST
   │
   │   constraint extraction
   ▼
{ hard_constraints[], soft_policy, governance, metadata }
   │
   │   serialize → bytecode
   ▼
PolicyBytecode  ───── deployable to PolicyEngine
   │
   │   hash
   ▼
PolicyHash  ───── stored in PolicyRegistry
```

The compilation is **deterministic** — the same `.hxp` source always produces the same bytecode and the same hash. This is essential: the treasury owner reads the `.hxp`, but the chain enforces the bytecode. The hash binds them.

## 7. Hard Constraints In Depth

Hard constraints are the safety floor. They have three properties:

**1. Declared at vault creation.** Hard constraints are set when a `TreasuryVault` is deployed and **cannot be relaxed**. They can be *tightened* via a separate governance flow with longer timelock.

**2. Evaluated post-execution, not just at proposal time.** The PolicyEngine simulates the proposed actions against current state and checks that every hard constraint holds after the simulation. If any hard constraint would be violated, the verdict is `Reject` — even if the soft policy says the action is correct.

**3. Independent of policy version.** When the treasury owner updates the soft policy, hard constraints are unchanged. This means a buggy or malicious policy update cannot bypass the safety floor.

### Standard Hard Constraints

We ship a library of common hard constraints. Treasury owners pick from this set or write custom ones (which must pass our verifier — see §8).

| ID | Predicate | Use case |
|---|---|---|
| `RUNWAY_FLOOR(months)` | Stablecoin runway ≥ N months | Never run out of operating capital |
| `MAX_SINGLE_ASSET(ratio, exclude)` | No single (non-excluded) asset exceeds ratio | Diversification |
| `MAX_DAILY_MOVEMENT(ratio)` | Total movement in 24h ≤ ratio × NAV | Anti-drain |
| `WHITELIST_ONLY(assets)` | Only hold assets in whitelist | Compliance |
| `BLACKLIST_NEVER(addresses)` | Never interact with sanctioned addresses | Sanctions screening |
| `MIN_ORACLE_SOURCES(n)` | Every price reference uses ≥ n oracles | Oracle resilience |
| `MAX_PROTOCOL_EXPOSURE(protocol, ratio)` | Exposure to single protocol ≤ ratio | Smart contract risk |
| `EMERGENCY_BRAKE` | If `freeze_flag` is set, reject all non-redeem actions | Incident response |

### Custom Hard Constraints

Custom constraints can be declared but must:

1. Be pure (no external calls except whitelisted built-ins)
2. Have bounded gas cost (verified at compile time via abstract interpretation)
3. Pass the `PolicyVerifier` check — which ensures the constraint is *monotonic* (relaxing a constraint requires explicit governance, not just clever syntax)

## 8. Policy Verifier

Before a policy is accepted by `PolicyRegistry`, it must pass the verifier:

```
verifier(policy_bytecode):
    1. parse bytecode → typed program
    2. check no I/O or external calls beyond whitelist
    3. check all loops are bounded
    4. compute upper bound on gas
    5. check that hard constraints set is ⊇ to current hard constraints
    6. check that custom constraints are monotonic
    7. return PASS or FAIL with reason
```

The verifier is open-source and reproducible. Anyone can run it on any policy bytecode.

## 9. Soft Policy Semantics

A soft policy's `allocation` block defines a *target state*. The PolicyEngine compares target state to current state and generates the **minimum action set** needed to reach the target, subject to `rebalance_when` and `max_rebalance_per_week`.

### Algorithm

```
def compute_actions(policy, state, market):
    if not policy.when_clause.eval(state, market):
        return []   # not the right time

    target_alloc = policy.target.eval(state, market)
    current_alloc = state.allocation()

    drift = max(|target[a] - current[a]| for a in assets)
    if drift < policy.rebalance_when:
        return []   # within tolerance

    if state.last_rebalance + 1 week > now():
        if policy.max_rebalance_per_week reached:
            return []

    # Compute minimum set of swaps to reach target
    return min_swap_plan(current_alloc, target_alloc)
```

### Minimum-swap planning

The `min_swap_plan` solves a flow problem: find the smallest set of swaps such that final allocation matches target within `drift` tolerance. This is deterministic and uses a fixed greedy algorithm (no off-chain solver) so that on-chain re-execution matches off-chain simulation.

## 10. Policy Update Flow

Policies are not immutable, but updates are gated:

```
Treasury Owner
    │
    │  1. drafts new .hxp
    │  2. compiles → new bytecode + hash
    │
    ▼
PolicyRegistry.proposeUpdate(new_hash)
    │
    │  emits PolicyUpdateProposed event
    │  enters 7-day public review window
    │
    ▼
After 7 days, Safe approval required
    │
    ▼
PolicyRegistry.activateUpdate(new_hash)
    │
    │  verifier runs again at activation
    │  checks new policy's hard constraints ⊇ current
    │
    ▼
new policy active
```

**Critical:** Hard constraints can only be *added*, not removed. The verifier enforces this. This means even a captured multisig cannot weaken the safety floor.

## 11. Example: Walking Through a Real Policy

Consider this real-world DAO policy:

```hxp
policy "dao-quarterly-treasury" {
    version: 1
    owner: 0xDAO_SAFE
    chain: arbitrum-one

    hard_constraint runway_floor {
        require: balance(state, USDC) + balance(state, USDT) >= 18 * 250000 USDC
        on_violation: reject
    }

    hard_constraint no_governance_token_dumps {
        require: balance(state, ARB) >= 0.95 * previous_balance(state, ARB, 30 days)
        on_violation: reject
    }

    allocation {
        when: total_value(state) > 18 * 250000 USDC + 1000000 USDC

        target: {
            USDC: keep(18 months runway)
            ARB: keep(current)              # never reduce
            BENJI: 0.40 of excess
            SPY_TOKEN: 0.30 of excess
            AAVE_USDC_SUPPLY: 0.30 of excess
        }

        rebalance_when: drift > 0.05
        max_rebalance_per_week: 1
    }
}
```

**Trigger event:** A grant proposal is rejected and 500K USDC returns to the treasury.

**Agent tick:**

1. Reads state: `USDC = 6M, ARB = 5M ARB, BENJI = 2M, SPY_TOKEN = 1.5M, AAVE_USDC = 1M`. NAV ≈ 19M USDC (oracle).
2. Computes `months_of_runway`: 6M / 250K = 24. Trigger fires.
3. Target: keep 4.5M USDC (18 months); excess is NAV - 4.5M - keep_ARB_value = 9.5M.
4. Target allocation: BENJI = 3.8M (currently 2M, diff +1.8M), SPY_TOKEN = 2.85M (currently 1.5M, diff +1.35M), AAVE_USDC = 2.85M (currently 1M, diff +1.85M).
5. Drift = max diff / NAV ≈ 0.10 > 0.05 → trigger rebalance.
6. Build proposal: deposit 1.85M to Aave, swap 1.8M USDC → BENJI, swap 1.35M USDC → SPY_TOKEN.
7. Simulate: post-state has runway = (6M - 1.85M - 1.8M - 1.35M) / 250K = 4 months. **Violates `runway_floor`!**
8. PolicyEngine would `Reject`. Agent re-plans: scale rebalance to keep runway ≥ 18 months exactly.
9. Re-simulate: passes all hard constraints.
10. Submit proposal to ProposalRegistry.

This walkthrough demonstrates the safety property: the agent's re-planning is not "trusted." Even if the agent had submitted the unsafe proposal, the on-chain PolicyEngine would have rejected it.

## 12. Stylus Implementation Notes

The PolicyEngine is implemented in Rust using the Stylus SDK. Key structural choices:

- **No `Vec` allocations in hot paths** — proposals are bounded to 32 actions; use `heapless::Vec` or fixed arrays.
- **Fixed-point arithmetic** — uses `fixed::U128F128` for all ratios; this matches the 18-decimal convention used on-chain.
- **Storage layout** — policies stored as content-addressable bytecode in mapping `policy_hash → bytecode`; lookup is O(1).
- **Re-entrancy safety** — Engine is purely a function over inputs; it makes no external calls during `evaluate()` except oracle reads via a single batched call.

See [docs/04-contracts.md](./04-contracts.md) for full storage layout and ABI.

## 13. Testing Strategy

The PolicyEngine has three test suites:

1. **Unit (Rust native)** — every built-in function, every constraint, every operator
2. **Property tests (proptest)** — invariants: e.g. *"for any state, any market, any policy, evaluate() returns either Approve or Reject with a documented reason, never a partial result"*
3. **Integration tests (Foundry)** — full flow: deploy → submit policy → submit proposal → evaluate → execute, with realistic scenarios

The property tests are the highest-leverage. We aim for >50 invariants by submission day.

## 14. What This Buys You vs. Existing Tools

| Tool | What it provides | What it doesn't |
|---|---|---|
| Safe alone | Multisig signing | No rules; no agent; no rebalancing |
| Den / Multis | Multisig + UX | Still manual; no enforced policy |
| Yearn / dHedge vaults | Strategy execution | Single strategy; not for org treasuries; not multi-asset |
| Karpatkey / Llama / StableLab (services) | Human treasurers | Expensive; not real-time; not enforced by code |
| **Helix** | **Policy as code + agent proposer + multisig enforcer + tax accounting** | (this is what's missing in the market) |
