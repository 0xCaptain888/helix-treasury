// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Helix shared types
/// @notice Types shared across PolicyEngine, ProposalRegistry, TreasuryVault, and adapters.
/// @dev Storage layouts referenced in docs/04-contracts.md.

/// @notice The kinds of treasury operations Helix supports.
enum ActionKind {
    NOOP,
    TRANSFER,
    SWAP,
    SUPPLY,
    WITHDRAW,
    BORROW,
    REPAY,
    BUY_RWA,
    SELL_RWA,
    REDEEM_RWA,
    BUY_PT,
    SELL_PT,
    BUY_YT,
    SELL_YT,
    REDEEM_PT_AT_MATURITY,
    SET_FLAG
}

/// @notice One treasury operation, dispatched to an adapter at execution time.
struct Action {
    ActionKind kind;
    address adapter;
    address asset;
    uint256 amount;
    bytes params; // adapter-specific encoding
}

/// @notice Snapshot of treasury state used by PolicyEngine.
struct TreasuryState {
    address[] assets;
    uint256[] balances; // parallel to assets
    uint256 totalNAVUsdc;
    uint64 snapshotAt;
    bytes32 stateHash;
}

/// @notice Snapshot of market state used by PolicyEngine.
struct MarketState {
    address[] assets;
    uint256[] pricesUsd6; // parallel to assets, 6 decimals
    uint64[] observedAt;
    bytes32 marketHash;
}

/// @notice Verdict returned by PolicyEngine.
enum VerdictKind {
    Approve,
    Reject,
    Stale
}

struct Verdict {
    VerdictKind kind;
    bytes32 policyHash;
    bytes32 computedActionsHash;
    bytes32 marketStateHash;
    uint64 evaluatedAt;
    bytes rejectReason;
}

/// @notice State machine for proposals.
enum ProposalState {
    Pending,
    Approved,
    Rejected,
    Executed,
    Cancelled,
    Expired
}

/// @notice Tax event kinds emitted at execution time.
enum TaxEventKind {
    REALIZED_GAIN,
    REALIZED_LOSS,
    DIVIDEND,
    STAKING_REWARD,
    CORPORATE_ACTION,
    INTERNAL_TRANSFER
}
