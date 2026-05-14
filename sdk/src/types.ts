/**
 * Shared types for the Helix SDK — mirrors on-chain HelixTypes.sol structs.
 * Used by HelixClient, policy tools, and the off-chain agent.
 */

import type { Address } from "viem";

// ─── Mirroring HelixTypes.sol ───

export type ActionKind =
  | "NOOP"
  | "ERC20_TRANSFER"
  | "AAVE_SUPPLY"
  | "AAVE_WITHDRAW"
  | "PENDLE_BUY_PT"
  | "PENDLE_SELL_PT"
  | "PENDLE_BUY_YT"
  | "PENDLE_SELL_YT"
  | "RWA_BUY"
  | "RWA_SELL"
  | "SWAP";

export interface Action {
  kind: ActionKind;
  asset: Address;
  amount: bigint;
  /** Protocol-specific data (e.g., Aave pool ID, Pendle market address) */
  data: `0x${string}`;
  /** Adapter contract address that will execute this action */
  adapter: Address;
  /** Minimum acceptable amount out — used for slippage protection */
  minAmountOut: bigint;
  /** Action expires if not executed before this timestamp */
  deadline: number;
}

export type VerdictKind = "Approve" | "SoftReject" | "HardReject" | "Stale";

export interface Verdict {
  kind: VerdictKind;
  /** Canonical action set recomputed by engine (for Approve: matches proposal; for Reject: shows what engine wanted) */
  canonicalActions: Action[];
  /** Typed rejection reason (if applicable) */
  rejectionCode: number;
  rejectionData: `0x${string}`;
  /** Commitment hash: keccak256(abi.encode(state, market)) — for audit trail */
  stateCommitment: `0x${string}`;
}

export type ProposalStateName =
  | "Submitted"
  | "PolicyAccepted"
  | "PolicyRejected"
  | "SafeApproved"
  | "Executed"
  | "Cancelled"
  | "Expired";

export interface MarketState {
  /** Token addresses */
  tokens: Address[];
  /** Prices in USDC-6 for each token (same index as tokens) */
  pricesUsdc: bigint[];
  /** Oracle timestamp for each price */
  priceTimestamps: number[];
  /** Aave supply APY in basis points for registered tokens */
  aaveApyBps: bigint[];
  /** Pendle implied APY for PT tokens in basis points */
  pendleApyBps: bigint[];
  /** 30-day rolling volatility in basis points (for drawdown calculations) */
  volatilityBps: bigint[];
  /** Block number at which market data was captured */
  capturedAt: number;
}

export interface AssetAllocation {
  token: Address;
  balanceRaw: bigint;
  priceUsdc: bigint;
  valueUsdc: bigint;
  allocationBps: number; // fraction of NAV in basis points
  protocol: "WALLET" | "AAVE" | "PENDLE_PT" | "PENDLE_YT" | "RWA";
}

export interface TreasurySnapshot {
  vaultAddress: Address;
  navUsdc: bigint;
  allocations: AssetAllocation[];
  paused: boolean;
  capturedAt: number;
  blockNumber: bigint;
}
