//! HXP Policy bytecode decoder.

use alloc::vec::Vec;
use alloy_primitives::{Address, FixedBytes, U256};

pub type ConstraintId = FixedBytes<32>;

pub const BYTECODE_MAGIC: u32 = 0x48454C58;

#[derive(Clone, Debug)]
pub struct Policy {
    pub hash: FixedBytes<32>,
    pub version: u32,
    pub owner: Address,
    pub hard_constraints: Vec<ConstraintId>,
    pub constraint_params: Vec<u8>,
    pub soft_policy: SoftPolicy,
}

#[derive(Clone, Debug, Default)]
pub struct SoftPolicy {
    pub targets: Vec<AllocationTarget>,
    pub rebalance_threshold_bps: u32,
    pub max_rebalances_per_week: u8,
}

#[derive(Clone, Debug)]
pub struct AllocationTarget {
    pub asset: Address,
    pub spec: TargetSpec,
    pub value: U256,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum TargetSpec {
    KeepRunwayMonths = 0,
    KeepCurrent      = 1,
    RatioOfExcess    = 2,
    RatioOfTotal     = 3,
    Remainder        = 4,
}

impl TryFrom<u8> for TargetSpec {
    type Error = &'static str;
    fn try_from(v: u8) -> Result<Self, Self::Error> {
        match v {
            0 => Ok(Self::KeepRunwayMonths),
            1 => Ok(Self::KeepCurrent),
            2 => Ok(Self::RatioOfExcess),
            3 => Ok(Self::RatioOfTotal),
            4 => Ok(Self::Remainder),
            _ => Err("unknown TargetSpec"),
        }
    }
}

pub fn decode_policy(bytes: &[u8], policy_hash: FixedBytes<32>) -> Result<Policy, &'static str> {
    let mut pos = 0;

    if bytes.len() < 4 { return Err("too short for magic"); }
    let magic = u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
    if magic != BYTECODE_MAGIC { return Err("bad magic"); }
    pos += 4;

    if bytes.len() < pos + 4 { return Err("too short for version"); }
    let version = u32::from_be_bytes([bytes[pos], bytes[pos+1], bytes[pos+2], bytes[pos+3]]);
    pos += 4;

    if bytes.len() < pos + 20 { return Err("too short for owner"); }
    let mut owner_bytes = [0u8; 20];
    owner_bytes.copy_from_slice(&bytes[pos..pos + 20]);
    let owner = Address::from(owner_bytes);
    pos += 20;

    if bytes.len() < pos + 2 { return Err("too short for n_constraints"); }
    let n_constraints = u16::from_be_bytes([bytes[pos], bytes[pos+1]]) as usize;
    pos += 2;

    if bytes.len() < pos + n_constraints * 32 { return Err("too short for constraint ids"); }
    let mut hard_constraints = Vec::new();
    for _ in 0..n_constraints {
        let mut id = [0u8; 32];
        id.copy_from_slice(&bytes[pos..pos + 32]);
        hard_constraints.push(FixedBytes::from(id));
        pos += 32;
    }

    if bytes.len() < pos + 4 { return Err("too short for params_len"); }
    let params_len = u32::from_be_bytes([bytes[pos], bytes[pos+1], bytes[pos+2], bytes[pos+3]]) as usize;
    pos += 4;
    if bytes.len() < pos + params_len { return Err("too short for params"); }
    let constraint_params = bytes[pos..pos + params_len].to_vec();
    pos += params_len;

    if bytes.len() < pos + 2 { return Err("too short for n_targets"); }
    let n_targets = u16::from_be_bytes([bytes[pos], bytes[pos+1]]) as usize;
    pos += 2;

    let mut targets = Vec::new();
    for _ in 0..n_targets {
        if bytes.len() < pos + 53 { return Err("too short for target"); }
        let mut asset_bytes = [0u8; 20];
        asset_bytes.copy_from_slice(&bytes[pos..pos + 20]);
        let asset = Address::from(asset_bytes);
        pos += 20;

        let spec = TargetSpec::try_from(bytes[pos])?;
        pos += 1;

        let mut val_bytes = [0u8; 32];
        val_bytes.copy_from_slice(&bytes[pos..pos + 32]);
        let value = U256::from_be_bytes(val_bytes);
        pos += 32;

        targets.push(AllocationTarget { asset, spec, value });
    }

    let rebalance_threshold_bps = if bytes.len() >= pos + 2 {
        let v = u16::from_be_bytes([bytes[pos], bytes[pos+1]]) as u32;
        pos += 2;
        v
    } else { 500 };

    let max_rebalances_per_week = if bytes.len() > pos {
        bytes[pos]
    } else { 1 };

    Ok(Policy {
        hash: policy_hash,
        version,
        owner,
        hard_constraints,
        constraint_params,
        soft_policy: SoftPolicy { targets, rebalance_threshold_bps, max_rebalances_per_week },
    })
}
