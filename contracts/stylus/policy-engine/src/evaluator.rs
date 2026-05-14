//! Soft-policy evaluator. Computes the canonical action set for given (state, market, policy).
//! See `docs/02-policy-engine.md §9`.

use crate::dsl::{Policy, SoftPolicy};
use crate::types::{Action, MarketState, TreasuryState};
use alloc::vec::Vec;

pub fn compute_actions(
    _policy: &Policy,
    _state: &TreasuryState,
    _market: &MarketState,
) -> Vec<Action> {
    // TODO(mulerun):
    //   1. if !eval(policy.soft_policy.when_expr, state, market): return vec![]
    //   2. target_alloc = resolve_targets(policy.soft_policy.targets, state, market)
    //   3. drift = max(|target[a] - current[a]| / total_nav)
    //   4. if drift < threshold: return vec![]
    //   5. if recent rebalance count >= max_per_week: return vec![]
    //   6. return min_swap_plan(current_alloc, target_alloc)
    Vec::new()
}

pub fn min_swap_plan(_current_balances: &[u128], _target_balances: &[u128]) -> Vec<Action> {
    // TODO(mulerun): deterministic greedy two-pointer over surpluses and deficits.
    //                Critical: must produce identical output to the TS simulator in the agent.
    Vec::new()
}
