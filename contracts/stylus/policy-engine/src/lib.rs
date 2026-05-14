//! # Helix PolicyEngine (Stylus / Rust)

#![cfg_attr(not(any(feature = "export-abi", test)), no_std)]
extern crate alloc;

// Provide native_keccak256 stub for tests (Stylus host function)
#[cfg(test)]
#[no_mangle]
pub extern "C" fn native_keccak256(input: *const u8, len: usize, output: *mut u8) {
    use tiny_keccak::{Hasher, Keccak};
    let data = unsafe { core::slice::from_raw_parts(input, len) };
    let mut hasher = Keccak::v256();
    hasher.update(data);
    let mut hash = [0u8; 32];
    hasher.finalize(&mut hash);
    unsafe { core::ptr::copy_nonoverlapping(hash.as_ptr(), output, 32) };
}

use alloc::vec::Vec;
use alloy_primitives::{Address, FixedBytes, U256};
use stylus_sdk::{prelude::*, storage::StorageAddress};

mod constraints;
mod dsl;
mod evaluator;
mod simulator;
mod types;

use constraints::{check_all, decode_context};
use dsl::decode_policy;
use simulator::apply_actions;
use types::{decode_actions, decode_treasury_state, encode_verdict, Verdict};

const MAX_MARKET_AGE_SECS: u64 = 120;

#[storage]
#[entrypoint]
pub struct PolicyEngine {
    policy_registry: StorageAddress,
}

#[public]
impl PolicyEngine {
    pub fn init(&mut self, registry: Address) -> Result<(), Vec<u8>> {
        if !self.policy_registry.get().is_zero() {
            return Err(b"already initialized".to_vec());
        }
        self.policy_registry.set(registry);
        Ok(())
    }

    pub fn evaluate(
        &self,
        policy_hash: FixedBytes<32>,
        state_bytes: Vec<u8>,
        _market_bytes: Vec<u8>,
        proposed_bytes: Vec<u8>,
    ) -> Result<Vec<u8>, Vec<u8>> {
        let state = decode_treasury_state(&state_bytes)
            .map_err(|e| e.as_bytes().to_vec())?;
        let proposed_actions = decode_actions(&proposed_bytes)
            .map_err(|e| e.as_bytes().to_vec())?;

        let registry = self.policy_registry.get();
        let policy = if registry.is_zero() {
            dsl::Policy {
                hash: policy_hash,
                version: 1,
                owner: Address::ZERO,
                hard_constraints: Vec::new(),
                constraint_params: Vec::new(),
                soft_policy: dsl::SoftPolicy::default(),
            }
        } else {
            let bytecode = load_policy_bytecode(registry, policy_hash)?;
            decode_policy(&bytecode, policy_hash)
                .map_err(|e| e.as_bytes().to_vec())?
        };

        let post_state = apply_actions(state.clone(), &proposed_actions);

        let ctx = decode_context(&policy.constraint_params);
        if let Err(failed_id) = check_all(
            &policy.hard_constraints,
            &post_state,
            &proposed_actions,
            &ctx,
        ) {
            let mut reason = b"HARD_CONSTRAINT_VIOLATION:".to_vec();
            reason.extend_from_slice(failed_id.as_slice());
            let verdict = Verdict::reject(policy_hash, &reason);
            return Ok(encode_verdict(&verdict));
        }

        let verdict = Verdict::approve(policy_hash, state.state_hash, state.snapshot_at);
        Ok(encode_verdict(&verdict))
    }

    pub fn check_hard_constraints(
        &self,
        policy_hash: FixedBytes<32>,
        state_bytes: Vec<u8>,
        actions_bytes: Vec<u8>,
    ) -> Result<Vec<u8>, Vec<u8>> {
        let state = decode_treasury_state(&state_bytes)
            .map_err(|e| e.as_bytes().to_vec())?;
        let actions = decode_actions(&actions_bytes)
            .map_err(|e| e.as_bytes().to_vec())?;

        let registry = self.policy_registry.get();
        let policy = if registry.is_zero() {
            dsl::Policy {
                hash: policy_hash, version: 1, owner: Address::ZERO,
                hard_constraints: Vec::new(), constraint_params: Vec::new(),
                soft_policy: dsl::SoftPolicy::default(),
            }
        } else {
            let bytecode = load_policy_bytecode(registry, policy_hash)?;
            decode_policy(&bytecode, policy_hash)
                .map_err(|e| e.as_bytes().to_vec())?
        };

        let post_state = apply_actions(state, &actions);
        let ctx = decode_context(&policy.constraint_params);

        match check_all(&policy.hard_constraints, &post_state, &actions, &ctx) {
            Ok(()) => {
                let mut out = [0u8; 64];
                out[31] = 1;
                Ok(out.to_vec())
            }
            Err(failed_id) => {
                let mut out = Vec::with_capacity(64);
                out.extend_from_slice(&[0u8; 32]);
                out.extend_from_slice(failed_id.as_slice());
                Ok(out)
            }
        }
    }

    pub fn get_registry(&self) -> Address {
        self.policy_registry.get()
    }
}

fn load_policy_bytecode(
    registry: Address,
    policy_hash: FixedBytes<32>,
) -> Result<Vec<u8>, Vec<u8>> {
    let selector: [u8; 4] = [0x93, 0xfe, 0x55, 0x39];
    let mut calldata = Vec::with_capacity(36);
    calldata.extend_from_slice(&selector);
    calldata.extend_from_slice(policy_hash.as_slice());

    let result = stylus_sdk::call::static_call(
        stylus_sdk::call::Call::new(),
        registry,
        &calldata,
    ).map_err(|_| b"policy_load_failed".to_vec())?;

    if result.len() < 96 {
        return Err(b"policy_response_too_short".to_vec());
    }
    let bytes_len_word = &result[64..96];
    let mut len_bytes = [0u8; 8];
    len_bytes.copy_from_slice(&bytes_len_word[24..32]);
    let bytes_len = u64::from_be_bytes(len_bytes) as usize;
    if result.len() < 96 + bytes_len {
        return Err(b"policy_bytes_truncated".to_vec());
    }
    Ok(result[96..96 + bytes_len].to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{TreasuryState, encode_verdict, Verdict, VerdictKind};
    use crate::constraints::{id_runway_floor, id_max_single_asset, id_max_daily_movement};
    use alloy_primitives::{U256, FixedBytes, Address, keccak256};

    fn make_state(nav: u64) -> TreasuryState {
        TreasuryState {
            assets: alloc::vec![Address::ZERO],
            balances: alloc::vec![U256::from(nav) * U256::from(1_000_000_000_000u64)],
            prices_usd6: alloc::vec![U256::from(1_000_000u64)],
            total_nav_usdc: U256::from(nav) * U256::from(1_000_000u64),
            snapshot_at: 0,
            state_hash: FixedBytes::ZERO,
        }
    }

    #[test]
    fn test_runway_floor_pass() {
        use crate::constraints::{CheckContext, check_all};
        let state = make_state(1_000_000);
        let mut ctx = CheckContext::default();
        ctx.runway_floor_months = 6;
        ctx.monthly_burn_usdc6 = U256::from(100_000u64) * U256::from(1_000_000u64);
        let stablecoin_bytes: [u8; 20] = Address::ZERO.into();
        ctx.stablecoin_assets.push(FixedBytes::from(stablecoin_bytes));

        let result = check_all(&alloc::vec![id_runway_floor()], &state, &[], &ctx);
        assert!(result.is_ok(), "runway_floor should pass with 10 months");
    }

    #[test]
    fn test_runway_floor_fail() {
        use crate::constraints::{CheckContext, check_all};
        let state = make_state(500_000);
        let mut ctx = CheckContext::default();
        ctx.runway_floor_months = 6;
        ctx.monthly_burn_usdc6 = U256::from(200_000u64) * U256::from(1_000_000u64);
        let stablecoin_bytes: [u8; 20] = Address::ZERO.into();
        ctx.stablecoin_assets.push(FixedBytes::from(stablecoin_bytes));

        let result = check_all(&alloc::vec![id_runway_floor()], &state, &[], &ctx);
        assert!(result.is_err(), "runway_floor should fail with 2.5 months");
        assert_eq!(result.unwrap_err(), id_runway_floor());
    }

    #[test]
    fn test_verdict_encode_approve() {
        let v = Verdict::approve(FixedBytes::ZERO, FixedBytes::ZERO, 12345);
        let encoded = encode_verdict(&v);
        assert!(encoded.len() >= 5 * 32);
        assert_eq!(encoded[31], 0);
    }

    #[test]
    fn test_verdict_encode_reject() {
        let v = Verdict::reject(FixedBytes::ZERO, b"HARD_CONSTRAINT_VIOLATION");
        let encoded = encode_verdict(&v);
        assert!(encoded.len() >= 6 * 32);
        assert_eq!(encoded[31], 1);
    }

    #[test]
    fn test_apply_actions_subtract() {
        use crate::simulator::apply_actions;
        use crate::types::Action;

        let state = make_state(1_000_000);
        let actions = alloc::vec![Action {
            kind: crate::types::KIND_TRANSFER,
            adapter: Address::ZERO,
            asset: Address::ZERO,
            amount: U256::from(100_000u64) * U256::from(1_000_000_000_000u64),
            params: alloc::vec![],
        }];
        let post = apply_actions(state, &actions);
        assert!(post.balances[0] < U256::from(1_000_000u64) * U256::from(1_000_000_000_000u64));
    }

    #[test]
    fn smoke() {
        assert_eq!(1 + 1, 2);
    }
}
