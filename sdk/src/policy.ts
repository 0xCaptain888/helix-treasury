/**
 * SDK policy utilities — parse, validate, and compile HXP policy files.
 * See docs/02-policy-engine.md for the HXP DSL specification.
 */

import { z } from "zod";

// ─── HXP Schema (runtime validation mirrors the Rust DSL types) ───

const HardConstraintSchema = z.object({
  id: z.string(),
  kind: z.enum([
    "MAX_SINGLE_ALLOCATION",
    "MIN_LIQUIDITY_RATIO",
    "MAX_COUNTERPARTY_EXPOSURE",
    "RUNWAY_FLOOR_DAYS",
    "MAX_DRAWDOWN",
    "MAX_DAILY_MOVEMENT",
    "STABLECOIN_FLOOR_RATIO",
  ]),
  params: z.record(z.string(), z.union([z.number(), z.string()])),
});

const SoftPolicySchema = z.object({
  id: z.string(),
  kind: z.enum([
    "TARGET_ALLOCATION",
    "REBALANCE_BAND",
    "YIELD_OPTIMIZATION",
    "RUNWAY_EXTENSION",
    "PENDLE_YIELD_CURVE",
    "RWA_ALLOCATION",
  ]),
  params: z.record(z.string(), z.union([z.number(), z.string()])),
  priority: z.number().int().min(1).max(100),
});

const PolicySchema = z.object({
  version: z.literal("0.1"),
  name: z.string().min(1).max(64),
  description: z.string().max(512).optional(),
  treasury: z.string().regex(/^0x[0-9a-fA-F]{40}$/),
  hard_constraints: z.array(HardConstraintSchema).min(1),
  soft_policies: z.array(SoftPolicySchema).min(1),
  metadata: z.object({
    author: z.string(),
    created_at: z.string(),
    tags: z.array(z.string()).optional(),
  }).optional(),
});

export type HXPPolicy = z.infer<typeof PolicySchema>;
export type HardConstraint = z.infer<typeof HardConstraintSchema>;
export type SoftPolicy = z.infer<typeof SoftPolicySchema>;

// ─── Parser ───

/**
 * Parse and validate an HXP policy from JSON string.
 * Throws ZodError with detailed messages on schema violations.
 */
export function parsePolicy(json: string): HXPPolicy {
  const raw = JSON.parse(json);
  return PolicySchema.parse(raw);
}

/**
 * Parse from an already-deserialized object (e.g., from YAML parse step).
 */
export function validatePolicy(raw: unknown): HXPPolicy {
  return PolicySchema.parse(raw);
}

// ─── Compiler stub ───

export interface CompileResult {
  /** ABI-encoded bytes ready for on-chain submission to PolicyRegistry */
  bytecode: `0x${string}`;
  /** keccak256 of bytecode — used as the policy hash on-chain */
  hash: `0x${string}`;
  /** Human-readable summary of what the policy encodes */
  summary: PolicySummary;
}

export interface PolicySummary {
  name: string;
  hardConstraintCount: number;
  softPolicyCount: number;
  /** Ordered list of hard constraints by strictness (most restrictive first) */
  hardConstraints: Array<{ id: string; kind: string; humanReadable: string }>;
}

/**
 * Compile a validated HXP policy to on-chain bytecode.
 *
 * TODO(mulerun): Actual encoding must match the Rust DSL decoder in
 * contracts/stylus/policy-engine/src/dsl.rs. Format:
 *   [4-byte version magic][uint16 hc_count][...hard constraints ABI-encoded][uint16 sp_count][...soft policies ABI-encoded]
 */
export async function compilePolicy(_policy: HXPPolicy): Promise<CompileResult> {
  throw new Error("Policy compiler not yet implemented — see docs/02-policy-engine.md §9");
}

// ─── Constraint helpers ───

/** Returns a human-readable description of a hard constraint */
export function describeConstraint(hc: HardConstraint): string {
  switch (hc.kind) {
    case "MAX_SINGLE_ALLOCATION":
      return `No single asset may exceed ${Number(hc.params.max_bps) / 100}% of NAV`;
    case "MIN_LIQUIDITY_RATIO":
      return `Liquid assets must remain ≥ ${Number(hc.params.min_bps) / 100}% of NAV`;
    case "MAX_COUNTERPARTY_EXPOSURE":
      return `Max ${Number(hc.params.max_bps) / 100}% exposure to any single counterparty`;
    case "RUNWAY_FLOOR_DAYS":
      return `Must maintain ≥ ${hc.params.days} days of operating runway in stables`;
    case "MAX_DRAWDOWN":
      return `Portfolio NAV must not fall more than ${Number(hc.params.max_bps) / 100}% from peak`;
    case "MAX_DAILY_MOVEMENT":
      return `Total assets moved per 24h ≤ ${Number(hc.params.max_bps) / 100}% of NAV`;
    case "STABLECOIN_FLOOR_RATIO":
      return `Stablecoins must comprise ≥ ${Number(hc.params.min_bps) / 100}% of NAV`;
    default:
      return `Constraint: ${hc.kind}`;
  }
}
