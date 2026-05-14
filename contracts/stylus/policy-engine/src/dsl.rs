//! HXP Policy bytecode decoder + in-memory representation.
//!
//! See `docs/02-policy-engine.md §3` (grammar) and §6 (compilation pipeline). The on-chain
//! representation is a compact deterministic bytecode produced by the off-chain compiler.

use alloc::vec::Vec;
use alloy_primitives::{Address, FixedBytes, U256};

/// Identifier of a built-in or custom hard constraint.
pub type ConstraintId = FixedBytes<32>;

#[derive(Clone, Debug)]
pub struct Policy {
    pub hash: FixedBytes<32>,
    pub version: u32,
    pub owner: Address,
    pub hard_constraints: Vec<HardConstraint>,
    pub soft_policy: SoftPolicy,
}

#[derive(Clone, Debug)]
pub struct HardConstraint {
    pub id: ConstraintId,
    /// Encoded predicate body (interpreted by the evaluator).
    pub predicate: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct SoftPolicy {
    /// Encoded `when` expression (trigger condition).
    pub when_expr: Vec<u8>,
    /// Allocation targets per asset.
    pub targets: Vec<AllocationTarget>,
    pub rebalance_threshold_bps: u32,
    pub max_rebalances_per_week: u8,
}

#[derive(Clone, Debug)]
pub struct AllocationTarget {
    pub asset: Address,
    pub spec: TargetSpec,
}

#[derive(Clone, Debug)]
pub enum TargetSpec {
    KeepRunwayMonths(u32),
    KeepCurrent,
    RatioOfExcess(U256), // 18-decimal fixed-point
    RatioOfTotal(U256),
    Remainder,
}

/// Decode policy bytecode produced by the off-chain compiler.
pub fn decode_policy(_bytes: &[u8]) -> Result<Policy, &'static str> {
    // TODO(mulerun): implement deterministic decoder
    Err("not implemented")
}
