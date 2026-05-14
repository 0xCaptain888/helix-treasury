//! # Helix PolicyEngine (Stylus / Rust)
//!
//! Pure evaluator. Stateless. Receives a policy hash, treasury state, market state, and a
//! proposed action set; returns a deterministic Verdict.
//!
//! See `docs/02-policy-engine.md` and `docs/04-contracts.md §1` for full specification.
//!
//! Design constraints:
//!   - no heap allocation in hot paths (use heapless::Vec, max 32 actions)
//!   - fixed-point arithmetic via `fixed::U128F128` for all ratios
//!   - all loops bounded; gas cost statically computable
//!   - reads from PolicyRegistry, TreasuryVault, OracleAggregator via Solidity ABI calls

#![cfg_attr(not(any(feature = "export-abi", test)), no_std)]
extern crate alloc;

use alloc::vec::Vec;
use alloy_primitives::{Address, FixedBytes, U256};
use stylus_sdk::{prelude::*, storage::StorageAddress};

mod constraints;
mod dsl;
mod evaluator;
mod simulator;
mod types;

use types::{Action, MarketState, TreasuryState, Verdict, VerdictKind};

#[storage]
#[entrypoint]
pub struct PolicyEngine {
    /// PolicyRegistry the engine reads bytecode from.
    policy_registry: StorageAddress,
}

#[public]
impl PolicyEngine {
    /// Initialize with the PolicyRegistry address.
    pub fn init(&mut self, registry: Address) -> Result<(), Vec<u8>> {
        if !self.policy_registry.get().is_zero() {
            return Err(b"already initialized".to_vec());
        }
        self.policy_registry.set(registry);
        Ok(())
    }

    /// Main evaluation entry point. See `docs/02-policy-engine.md §1` for semantics.
    ///
    /// # Returns
    /// A deterministic `Verdict::Approve` if and only if:
    ///   1. The market commitment matches live oracle within tolerance.
    ///   2. All hard constraints hold for the simulated post-state.
    ///   3. The computed canonical action set matches the proposed actions.
    ///
    /// Otherwise returns `Verdict::Reject` with a typed reason, or `Verdict::Stale`.
    pub fn evaluate(
        &self,
        _policy_hash: FixedBytes<32>,
        _state_bytes: Vec<u8>,
        _market_bytes: Vec<u8>,
        _proposed_bytes: Vec<u8>,
    ) -> Result<Vec<u8>, Vec<u8>> {
        // TODO(mulerun):
        //   1. Decode state, market, proposed from ABI bytes
        //   2. Load policy from registry via static call
        //   3. Decode policy bytecode -> dsl::Policy
        //   4. Verify market commitment freshness vs live oracle
        //   5. Simulate proposed actions -> post_state
        //   6. for constraint in policy.hard_constraints: check holds(post_state)
        //   7. canonical = evaluator::compute_actions(&policy, &state, &market)
        //   8. if canonical hash != proposed hash → Reject
        //   9. ABI-encode Verdict and return
        Err(b"not implemented".to_vec())
    }

    /// Cheaper helper: just check hard constraints against a hypothetical post-state.
    pub fn check_hard_constraints(
        &self,
        _policy_hash: FixedBytes<32>,
        _post_state_bytes: Vec<u8>,
    ) -> Result<Vec<u8>, Vec<u8>> {
        // TODO(mulerun): returns (bool ok, bytes failedConstraint)
        Err(b"not implemented".to_vec())
    }

    /// Pure recomputation of canonical action set — used by off-chain simulators
    /// to obtain the engine's view of what the proposal "should" look like.
    pub fn compute_actions(
        &self,
        _policy_hash: FixedBytes<32>,
        _state_bytes: Vec<u8>,
        _market_bytes: Vec<u8>,
    ) -> Result<Vec<u8>, Vec<u8>> {
        // TODO(mulerun): same as step 7 of evaluate, but returned directly
        Err(b"not implemented".to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smoke() {
        // Property tests live in `tests/proptest_*.rs` once evaluator is fleshed out.
    }
}
