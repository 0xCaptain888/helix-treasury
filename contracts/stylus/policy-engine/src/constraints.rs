//! Standard hard constraints library. See `docs/02-policy-engine.md §7`.

use crate::dsl::ConstraintId;
use crate::types::{Action, TreasuryState};
use alloc::vec::Vec;
use alloy_primitives::{keccak256, FixedBytes, U256};

/// Returns true if all named constraints hold against `post_state`.
pub fn check_all(
    _ids: &[ConstraintId],
    _post_state: &TreasuryState,
    _ctx: &CheckContext,
) -> Result<(), ConstraintId> {
    // TODO(mulerun): dispatch to per-constraint check_X
    Err(FixedBytes::ZERO)
}

#[derive(Clone, Debug, Default)]
pub struct CheckContext {
    pub monthly_burn_usdc: U256,
    pub total_movement_24h_usdc: U256,
    pub total_value_pre_usdc: U256,
}

// ──────────── Standard constraint IDs ────────────
//
// Each constraint has a deterministic ID = keccak256(name).
// The off-chain compiler embeds these IDs in the policy bytecode.

pub fn id_runway_floor() -> ConstraintId {
    keccak256(b"RUNWAY_FLOOR")
}
pub fn id_max_single_asset() -> ConstraintId {
    keccak256(b"MAX_SINGLE_ASSET")
}
pub fn id_max_daily_movement() -> ConstraintId {
    keccak256(b"MAX_DAILY_MOVEMENT")
}
pub fn id_whitelist_only() -> ConstraintId {
    keccak256(b"WHITELIST_ONLY")
}
pub fn id_blacklist_never() -> ConstraintId {
    keccak256(b"BLACKLIST_NEVER")
}
pub fn id_min_oracle_sources() -> ConstraintId {
    keccak256(b"MIN_ORACLE_SOURCES")
}
pub fn id_max_protocol_exposure() -> ConstraintId {
    keccak256(b"MAX_PROTOCOL_EXPOSURE")
}
pub fn id_emergency_brake() -> ConstraintId {
    keccak256(b"EMERGENCY_BRAKE")
}

// ──────────── Per-constraint checkers (skeletons) ────────────

#[allow(dead_code)]
fn check_runway_floor(_state: &TreasuryState, _ctx: &CheckContext) -> bool {
    // TODO(mulerun): runway = sum(stablecoin balances) / monthly_burn; require >= floor
    false
}

#[allow(dead_code)]
fn check_max_single_asset(_state: &TreasuryState) -> bool {
    // TODO(mulerun): for asset in non-excluded: ratio = balance/total_nav; require <= cap
    false
}

#[allow(dead_code)]
fn check_max_daily_movement(_actions: &[Action], _ctx: &CheckContext) -> bool {
    // TODO(mulerun): sum of action volumes + ctx.total_movement_24h_usdc <= cap_ratio * total
    false
}
