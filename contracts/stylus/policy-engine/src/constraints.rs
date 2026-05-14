//! Standard hard constraints. See `docs/02-policy-engine.md §7`.

use crate::types::{balance_of, compute_nav, price_of, Action, TreasuryState};
use alloc::vec::Vec;
use alloy_primitives::{keccak256, FixedBytes, U256};

pub type ConstraintId = FixedBytes<32>;

pub fn id_runway_floor() -> ConstraintId { keccak256(b"RUNWAY_FLOOR") }
pub fn id_max_single_asset() -> ConstraintId { keccak256(b"MAX_SINGLE_ASSET") }
pub fn id_max_daily_movement() -> ConstraintId { keccak256(b"MAX_DAILY_MOVEMENT") }
pub fn id_whitelist_only() -> ConstraintId { keccak256(b"WHITELIST_ONLY") }
pub fn id_blacklist_never() -> ConstraintId { keccak256(b"BLACKLIST_NEVER") }
pub fn id_min_oracle_sources() -> ConstraintId { keccak256(b"MIN_ORACLE_SOURCES") }
pub fn id_max_protocol_exposure() -> ConstraintId { keccak256(b"MAX_PROTOCOL_EXPOSURE") }
pub fn id_stablecoin_floor() -> ConstraintId { keccak256(b"STABLECOIN_FLOOR") }
pub fn id_emergency_brake() -> ConstraintId { keccak256(b"EMERGENCY_BRAKE") }

#[derive(Clone, Debug, Default)]
pub struct CheckContext {
    pub stablecoin_assets: Vec<FixedBytes<20>>,
    pub monthly_burn_usdc6: U256,
    pub movement_24h_usdc6: U256,
    pub max_single_asset_bps: u32,
    pub max_daily_movement_bps: u32,
    pub min_stablecoin_bps: u32,
    pub runway_floor_months: u32,
    pub max_protocol_exposure_bps: u32,
    pub emergency_brake_active: bool,
    pub whitelist: Vec<[u8; 20]>,
    pub blacklist: Vec<[u8; 20]>,
}

pub fn check_all(
    ids: &[ConstraintId],
    post_state: &TreasuryState,
    actions: &[Action],
    ctx: &CheckContext,
) -> Result<(), ConstraintId> {
    let nav = if post_state.total_nav_usdc.is_zero() {
        compute_nav(&post_state.balances, &post_state.prices_usd6)
    } else {
        post_state.total_nav_usdc
    };

    for id in ids {
        if *id == id_runway_floor() {
            if !check_runway_floor(post_state, ctx, nav) { return Err(*id); }
        } else if *id == id_max_single_asset() {
            if !check_max_single_asset(post_state, ctx, nav) { return Err(*id); }
        } else if *id == id_max_daily_movement() {
            if !check_max_daily_movement(actions, ctx, nav) { return Err(*id); }
        } else if *id == id_whitelist_only() {
            if !check_whitelist(actions, ctx) { return Err(*id); }
        } else if *id == id_blacklist_never() {
            if !check_blacklist(actions, ctx) { return Err(*id); }
        } else if *id == id_max_protocol_exposure() {
            if !check_max_protocol_exposure(post_state, ctx, nav) { return Err(*id); }
        } else if *id == id_stablecoin_floor() {
            if !check_stablecoin_floor(post_state, ctx, nav) { return Err(*id); }
        } else if *id == id_emergency_brake() {
            if ctx.emergency_brake_active {
                for action in actions {
                    if action.kind != 0 && action.kind != 4 {
                        return Err(*id);
                    }
                }
            }
        }
    }
    Ok(())
}

fn check_runway_floor(state: &TreasuryState, ctx: &CheckContext, _nav: U256) -> bool {
    if ctx.monthly_burn_usdc6.is_zero() { return true; }
    if ctx.runway_floor_months == 0 { return true; }
    let stablecoin_balance_usdc6 = sum_stablecoin_value(state, ctx);
    let required = ctx.monthly_burn_usdc6.saturating_mul(U256::from(ctx.runway_floor_months));
    stablecoin_balance_usdc6 >= required
}

fn check_max_single_asset(state: &TreasuryState, ctx: &CheckContext, nav: U256) -> bool {
    if nav.is_zero() || ctx.max_single_asset_bps == 0 { return true; }
    let cap_bps = U256::from(ctx.max_single_asset_bps);
    let denom = U256::from(10_000u32);
    let divisor = U256::from(1_000_000_000_000u64);
    for (i, asset) in state.assets.iter().enumerate() {
        if is_stablecoin(asset, ctx) { continue; }
        let bal = state.balances.get(i).copied().unwrap_or(U256::ZERO);
        let price = state.prices_usd6.get(i).copied().unwrap_or(U256::ZERO);
        let value = bal.saturating_mul(price) / divisor;
        if value.saturating_mul(denom) > nav.saturating_mul(cap_bps) {
            return false;
        }
    }
    true
}

fn check_max_daily_movement(actions: &[Action], ctx: &CheckContext, nav: U256) -> bool {
    if nav.is_zero() || ctx.max_daily_movement_bps == 0 { return true; }
    let divisor = U256::from(1_000_000_000_000u64);
    let mut new_movement = U256::ZERO;
    for action in actions {
        if action.kind != 0 {
            new_movement = new_movement.saturating_add(action.amount / divisor);
        }
    }
    let total = ctx.movement_24h_usdc6.saturating_add(new_movement);
    let cap = nav.saturating_mul(U256::from(ctx.max_daily_movement_bps)) / U256::from(10_000u32);
    total <= cap
}

fn check_whitelist(actions: &[Action], ctx: &CheckContext) -> bool {
    if ctx.whitelist.is_empty() { return true; }
    for action in actions {
        let asset_bytes: [u8; 20] = action.asset.into();
        let adapter_bytes: [u8; 20] = action.adapter.into();
        let asset_ok = ctx.whitelist.iter().any(|w| *w == asset_bytes);
        let adapter_ok = ctx.whitelist.iter().any(|w| *w == adapter_bytes) || action.adapter.is_zero();
        if !asset_ok || !adapter_ok { return false; }
    }
    true
}

fn check_blacklist(actions: &[Action], ctx: &CheckContext) -> bool {
    if ctx.blacklist.is_empty() { return true; }
    for action in actions {
        let asset_bytes: [u8; 20] = action.asset.into();
        let adapter_bytes: [u8; 20] = action.adapter.into();
        if ctx.blacklist.iter().any(|b| *b == asset_bytes || *b == adapter_bytes) {
            return false;
        }
    }
    true
}

fn check_max_protocol_exposure(state: &TreasuryState, ctx: &CheckContext, nav: U256) -> bool {
    if nav.is_zero() || ctx.max_protocol_exposure_bps == 0 { return true; }
    check_max_single_asset(state, ctx, nav)
}

fn check_stablecoin_floor(state: &TreasuryState, ctx: &CheckContext, nav: U256) -> bool {
    if nav.is_zero() || ctx.min_stablecoin_bps == 0 { return true; }
    let stable_val = sum_stablecoin_value(state, ctx);
    let required = nav.saturating_mul(U256::from(ctx.min_stablecoin_bps)) / U256::from(10_000u32);
    stable_val >= required
}

fn sum_stablecoin_value(state: &TreasuryState, ctx: &CheckContext) -> U256 {
    let divisor = U256::from(1_000_000_000_000u64);
    let mut total = U256::ZERO;
    for (i, asset) in state.assets.iter().enumerate() {
        if is_stablecoin(asset, ctx) {
            let bal = state.balances.get(i).copied().unwrap_or(U256::ZERO);
            let price = state.prices_usd6.get(i).copied().unwrap_or(U256::from(1_000_000u64));
            total = total.saturating_add(bal.saturating_mul(price) / divisor);
        }
    }
    total
}

fn is_stablecoin(asset: &alloy_primitives::Address, ctx: &CheckContext) -> bool {
    let bytes: [u8; 20] = (*asset).into();
    ctx.stablecoin_assets.iter().any(|s| s.as_slice() == bytes)
}

pub fn decode_context(params: &[u8]) -> CheckContext {
    let mut ctx = CheckContext::default();
    let mut i = 0;
    while i + 33 <= params.len() {
        let key = params[i];
        let val = &params[i + 1..i + 33];
        match key {
            0x01 => ctx.runway_floor_months = u32::from_be_bytes([val[28], val[29], val[30], val[31]]),
            0x02 => ctx.monthly_burn_usdc6 = U256::from_be_slice(val),
            0x03 => ctx.max_single_asset_bps = u32::from_be_bytes([val[28], val[29], val[30], val[31]]),
            0x04 => ctx.max_daily_movement_bps = u32::from_be_bytes([val[28], val[29], val[30], val[31]]),
            0x05 => ctx.min_stablecoin_bps = u32::from_be_bytes([val[28], val[29], val[30], val[31]]),
            0x06 => ctx.max_protocol_exposure_bps = u32::from_be_bytes([val[28], val[29], val[30], val[31]]),
            0x07 => {
                let mut addr = [0u8; 20];
                addr.copy_from_slice(&val[12..32]);
                ctx.stablecoin_assets.push(FixedBytes::from(addr));
            },
            0x08 => {
                let mut addr = [0u8; 20];
                addr.copy_from_slice(&val[12..32]);
                ctx.blacklist.push(addr);
            },
            0x09 => {
                let mut addr = [0u8; 20];
                addr.copy_from_slice(&val[12..32]);
                ctx.whitelist.push(addr);
            },
            0x0A => ctx.emergency_brake_active = val[31] != 0,
            _ => {}
        }
        i += 33;
    }
    ctx
}
