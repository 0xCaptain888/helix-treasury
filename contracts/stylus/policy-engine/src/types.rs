//! Shared types for the PolicyEngine. Mirrors `contracts/solidity/HelixTypes.sol`.

use alloy_primitives::{Address, FixedBytes, U256};
use alloc::vec::Vec;

#[derive(Clone, Debug)]
pub struct Action {
    pub kind: u8,
    pub adapter: Address,
    pub asset: Address,
    pub amount: U256,
    pub params: Vec<u8>,
}

#[derive(Clone, Debug)]
pub struct TreasuryState {
    pub assets: Vec<Address>,
    pub balances: Vec<U256>,
    pub total_nav_usdc: U256,
    pub snapshot_at: u64,
    pub state_hash: FixedBytes<32>,
}

#[derive(Clone, Debug)]
pub struct MarketState {
    pub assets: Vec<Address>,
    pub prices_usd6: Vec<U256>,
    pub observed_at: Vec<u64>,
    pub market_hash: FixedBytes<32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum VerdictKind {
    Approve,
    Reject,
    Stale,
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
