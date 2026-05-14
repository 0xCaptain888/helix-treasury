//! Shared types for the PolicyEngine. Mirrors `contracts/solidity/HelixTypes.sol`.
//! All decode/encode uses manual ABI layout (uint256 = 32 bytes, address = 32 bytes padded).

use alloy_primitives::{Address, FixedBytes, U256};
use alloc::vec::Vec;

// ─── Action kinds (mirrors ActionKind enum in HelixTypes.sol) ───

pub const KIND_NOOP: u8 = 0;
pub const KIND_TRANSFER: u8 = 1;
pub const KIND_SWAP: u8 = 2;
pub const KIND_SUPPLY: u8 = 3;
pub const KIND_WITHDRAW: u8 = 4;
pub const KIND_BORROW: u8 = 5;
pub const KIND_REPAY: u8 = 6;
pub const KIND_BUY_RWA: u8 = 7;
pub const KIND_SELL_RWA: u8 = 8;
pub const KIND_REDEEM_RWA: u8 = 9;
pub const KIND_BUY_PT: u8 = 10;
pub const KIND_SELL_PT: u8 = 11;
pub const KIND_SET_FLAG: u8 = 12;

#[derive(Clone, Debug, Default)]
pub struct Action {
    pub kind: u8,
    pub adapter: Address,
    pub asset: Address,
    pub amount: U256,
    pub params: Vec<u8>,
}

#[derive(Clone, Debug, Default)]
pub struct TreasuryState {
    pub assets: Vec<Address>,
    pub balances: Vec<U256>,
    pub prices_usd6: Vec<U256>,
    pub total_nav_usdc: U256,
    pub snapshot_at: u64,
    pub state_hash: FixedBytes<32>,
}

#[derive(Clone, Debug, Default)]
pub struct MarketState {
    pub assets: Vec<Address>,
    pub prices_usd6: Vec<U256>,
    pub observed_at: Vec<u64>,
    pub market_hash: FixedBytes<32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VerdictKind {
    Approve = 0,
    Reject = 1,
    Stale = 2,
}

#[derive(Clone, Debug)]
pub struct Verdict {
    pub kind: VerdictKind,
    pub policy_hash: FixedBytes<32>,
    pub computed_actions_hash: FixedBytes<32>,
    pub market_state_hash: FixedBytes<32>,
    pub evaluated_at: u64,
    pub reject_reason: Vec<u8>,
}

impl Verdict {
    pub fn approve(policy_hash: FixedBytes<32>, market_hash: FixedBytes<32>, at: u64) -> Self {
        Self {
            kind: VerdictKind::Approve,
            policy_hash,
            computed_actions_hash: FixedBytes::ZERO,
            market_state_hash: market_hash,
            evaluated_at: at,
            reject_reason: Vec::new(),
        }
    }

    pub fn reject(policy_hash: FixedBytes<32>, reason: &[u8]) -> Self {
        Self {
            kind: VerdictKind::Reject,
            policy_hash,
            computed_actions_hash: FixedBytes::ZERO,
            market_state_hash: FixedBytes::ZERO,
            evaluated_at: 0,
            reject_reason: reason.to_vec(),
        }
    }

    pub fn stale(reason: &[u8]) -> Self {
        Self {
            kind: VerdictKind::Stale,
            policy_hash: FixedBytes::ZERO,
            computed_actions_hash: FixedBytes::ZERO,
            market_state_hash: FixedBytes::ZERO,
            evaluated_at: 0,
            reject_reason: reason.to_vec(),
        }
    }
}

pub fn read_u256(buf: &[u8], offset: usize) -> Option<U256> {
    if offset + 32 > buf.len() { return None; }
    Some(U256::from_be_slice(&buf[offset..offset + 32]))
}

pub fn read_address(buf: &[u8], offset: usize) -> Option<Address> {
    if offset + 32 > buf.len() { return None; }
    let mut bytes = [0u8; 20];
    bytes.copy_from_slice(&buf[offset + 12..offset + 32]);
    Some(Address::from(bytes))
}

pub fn read_u64(buf: &[u8], offset: usize) -> Option<u64> {
    let v = read_u256(buf, offset)?;
    Some(v.to::<u64>())
}

pub fn read_bytes32(buf: &[u8], offset: usize) -> Option<FixedBytes<32>> {
    if offset + 32 > buf.len() { return None; }
    let mut out = [0u8; 32];
    out.copy_from_slice(&buf[offset..offset + 32]);
    Some(FixedBytes::from(out))
}

pub fn decode_treasury_state(buf: &[u8]) -> Result<TreasuryState, &'static str> {
    if buf.len() < 5 * 32 { return Err("treasury_state: too short"); }
    let n = read_u256(buf, 0).ok_or("bad assets_len")?.to::<usize>();
    let total_nav = read_u256(buf, 2 * 32).ok_or("bad nav")?;
    let snapshot_at = read_u64(buf, 3 * 32).ok_or("bad snapshot_at")?;
    let state_hash = read_bytes32(buf, 4 * 32).ok_or("bad state_hash")?;
    let base = 5 * 32;
    if buf.len() < base + n * 32 * 3 { return Err("treasury_state: data truncated"); }
    let mut assets = Vec::new();
    let mut balances = Vec::new();
    let mut prices = Vec::new();
    for i in 0..n {
        assets.push(read_address(buf, base + i * 32).ok_or("bad asset addr")?);
        balances.push(read_u256(buf, base + n * 32 + i * 32).ok_or("bad balance")?);
        prices.push(read_u256(buf, base + 2 * n * 32 + i * 32).ok_or("bad price")?);
    }
    Ok(TreasuryState { assets, balances, prices_usd6: prices, total_nav_usdc: total_nav, snapshot_at, state_hash })
}

pub fn decode_actions(buf: &[u8]) -> Result<Vec<Action>, &'static str> {
    if buf.len() < 32 { return Err("actions: too short"); }
    let count = read_u256(buf, 0).ok_or("bad count")?.to::<usize>();
    if count > 32 { return Err("actions: too many (max 32)"); }
    let mut actions = Vec::new();
    let mut offset = 32;
    for _ in 0..count {
        if offset + 5 * 32 > buf.len() { return Err("actions: truncated"); }
        let kind = read_u256(buf, offset).ok_or("bad kind")?.to::<u8>();
        let adapter = read_address(buf, offset + 32).ok_or("bad adapter")?;
        let asset = read_address(buf, offset + 64).ok_or("bad asset")?;
        let amount = read_u256(buf, offset + 96).ok_or("bad amount")?;
        let params_len = read_u256(buf, offset + 128).ok_or("bad params_len")?.to::<usize>();
        offset += 5 * 32;
        let params = if params_len == 0 {
            Vec::new()
        } else {
            if offset + params_len > buf.len() { return Err("actions: params truncated"); }
            let p = buf[offset..offset + params_len].to_vec();
            offset += (params_len + 31) / 32 * 32;
            p
        };
        actions.push(Action { kind, adapter, asset, amount, params });
    }
    Ok(actions)
}

pub fn encode_verdict(v: &Verdict) -> Vec<u8> {
    let mut out = Vec::new();
    let mut kind_bytes = [0u8; 32];
    kind_bytes[31] = v.kind as u8;
    out.extend_from_slice(&kind_bytes);
    out.extend_from_slice(v.policy_hash.as_slice());
    out.extend_from_slice(v.computed_actions_hash.as_slice());
    out.extend_from_slice(v.market_state_hash.as_slice());
    let mut at_bytes = [0u8; 32];
    at_bytes[24..].copy_from_slice(&v.evaluated_at.to_be_bytes());
    out.extend_from_slice(&at_bytes);
    let mut len_bytes = [0u8; 32];
    let rlen = v.reject_reason.len();
    len_bytes[24..].copy_from_slice(&(rlen as u64).to_be_bytes());
    out.extend_from_slice(&len_bytes);
    if rlen > 0 {
        out.extend_from_slice(&v.reject_reason);
        let pad = (32 - rlen % 32) % 32;
        out.extend(core::iter::repeat(0u8).take(pad));
    }
    out
}

pub fn compute_nav(balances: &[U256], prices_usd6: &[U256]) -> U256 {
    let divisor = U256::from(1_000_000_000_000u64);
    let mut nav = U256::ZERO;
    let n = balances.len().min(prices_usd6.len());
    for i in 0..n {
        let value = balances[i].saturating_mul(prices_usd6[i]) / divisor;
        nav = nav.saturating_add(value);
    }
    nav
}

pub fn price_of(state: &TreasuryState, asset: &Address) -> U256 {
    for (i, a) in state.assets.iter().enumerate() {
        if a == asset {
            return state.prices_usd6.get(i).copied().unwrap_or(U256::ZERO);
        }
    }
    U256::ZERO
}

pub fn balance_of(state: &TreasuryState, asset: &Address) -> U256 {
    for (i, a) in state.assets.iter().enumerate() {
        if a == asset {
            return state.balances.get(i).copied().unwrap_or(U256::ZERO);
        }
    }
    U256::ZERO
}
