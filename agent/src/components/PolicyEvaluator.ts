/**
 * PolicyEvaluator — TypeScript twin of the Stylus PolicyEngine.
 *
 * Must produce identical outputs to the on-chain engine; kept in sync via shared test corpus
 * in `test/policy-corpus/`. See docs/03-execution-agent.md §3.2.
 */

import type { Logger } from "pino";
import type { Config } from "../config.js";
import type { ActivePolicy, TreasuryStateSnapshot, MarketStateSnapshot } from "./MarketMonitor.js";

export type EvaluatorResult =
  | { kind: "no-trigger" }
  | { kind: "trigger"; actions: Action[]; rationale: string }
  | { kind: "violation"; reason: string };

export interface Action {
  kind: number;
  adapter: `0x${string}`;
  asset: `0x${string}`;
  amount: bigint;
  params: `0x${string}`;
}

export class PolicyEvaluator {
  constructor(private readonly config: Config, private readonly log: Logger) {}

  async evaluate(
    _state: TreasuryStateSnapshot,
    _market: MarketStateSnapshot,
    _policy: ActivePolicy,
  ): Promise<EvaluatorResult> {
    // TODO(mulerun): decode policy bytecode, evaluate `when`, compute target alloc,
    // produce min-swap plan. Must match Stylus implementation byte-for-byte.
    return { kind: "no-trigger" };
  }

  async repair(
    _state: TreasuryStateSnapshot,
    _market: MarketStateSnapshot,
    _policy: ActivePolicy,
    _violations: string[],
  ): Promise<{ actions: Action[] } | null> {
    // TODO(mulerun): attempt to scale-down actions until all hard constraints satisfy
    return null;
  }
}
