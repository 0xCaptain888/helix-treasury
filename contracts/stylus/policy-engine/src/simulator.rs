//! Apply a sequence of Actions to a TreasuryState to get the post-execution state.

use alloc::vec::Vec;
use crate::types::{Action, TreasuryState, KIND_SUPPLY, KIND_WITHDRAW, KIND_TRANSFER,
                   KIND_SWAP, KIND_BUY_RWA, KIND_SELL_RWA, KIND_BUY_PT, KIND_SELL_PT, compute_nav};
use alloy_primitives::{keccak256, U256};

pub fn apply_actions(state: TreasuryState, actions: &[Action]) -> TreasuryState {
    let mut s = state.clone();

    for action in actions {
        match action.kind {
            k if k == KIND_TRANSFER || k == KIND_SELL_RWA || k == KIND_SELL_PT => {
                subtract_balance(&mut s, &action.asset, action.amount);
            }
            k if k == KIND_SUPPLY => {
                // Balance stays same in NAV terms
            }
            k if k == KIND_WITHDRAW => {
                add_balance(&mut s, &action.asset, action.amount);
            }
            k if k == KIND_SWAP => {
                subtract_balance(&mut s, &action.asset, action.amount);
                if action.params.len() >= 20 {
                    let mut token_out_bytes = [0u8; 20];
                    token_out_bytes.copy_from_slice(&action.params[0..20]);
                    let token_out = alloy_primitives::Address::from(token_out_bytes);
                    let price_in = price_of_in_state(&s, &action.asset);
                    let price_out = price_of_in_state(&s, &token_out);
                    let divisor = U256::from(1_000_000_000_000u64);
                    let value_in_usdc6 = action.amount.saturating_mul(price_in) / divisor;
                    let amount_out = if !price_out.is_zero() {
                        value_in_usdc6.saturating_mul(divisor) / price_out
                    } else {
                        U256::ZERO
                    };
                    add_balance(&mut s, &token_out, amount_out);
                }
            }
            k if k == KIND_BUY_RWA || k == KIND_BUY_PT => {
                if action.params.len() >= 20 {
                    let mut pay_bytes = [0u8; 20];
                    pay_bytes.copy_from_slice(&action.params[0..20]);
                    let pay_token = alloy_primitives::Address::from(pay_bytes);
                    subtract_balance(&mut s, &pay_token, action.amount);
                }
                add_balance(&mut s, &action.asset, action.amount);
            }
            _ => {}
        }
    }

    s.total_nav_usdc = compute_nav(&s.balances, &s.prices_usd6);
    let mut hash_input = Vec::new();
    for (i, a) in s.assets.iter().enumerate() {
        hash_input.extend_from_slice(a.as_slice());
        let bal = s.balances.get(i).copied().unwrap_or(U256::ZERO);
        hash_input.extend_from_slice(&bal.to_be_bytes::<32>());
    }
    s.state_hash = keccak256(&hash_input);
    s
}

fn subtract_balance(state: &mut TreasuryState, asset: &alloy_primitives::Address, amount: U256) {
    for (i, a) in state.assets.iter().enumerate() {
        if a == asset {
            if let Some(bal) = state.balances.get_mut(i) {
                *bal = bal.saturating_sub(amount);
            }
            return;
        }
    }
}

fn add_balance(state: &mut TreasuryState, asset: &alloy_primitives::Address, amount: U256) {
    for (i, a) in state.assets.iter().enumerate() {
        if a == asset {
            if let Some(bal) = state.balances.get_mut(i) {
                *bal = bal.saturating_add(amount);
            }
            return;
        }
    }
    state.assets.push(*asset);
    state.balances.push(amount);
    state.prices_usd6.push(U256::ZERO);
}

fn price_of_in_state(state: &TreasuryState, asset: &alloy_primitives::Address) -> U256 {
    for (i, a) in state.assets.iter().enumerate() {
        if a == asset {
            return state.prices_usd6.get(i).copied().unwrap_or(U256::ZERO);
        }
    }
    U256::ZERO
}
