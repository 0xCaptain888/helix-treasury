/**
 * Helix Execution Agent — entry point.
 *
 * The Agent observes treasury and market state, evaluates active policies, simulates candidate
 * action sets against hard constraints, and submits proposals to ProposalRegistry. It does NOT
 * have execution authority; every proposal is gated by PolicyEngine, Safe multisig, and timelock.
 *
 * See docs/03-execution-agent.md for full design.
 */

import { loadConfig } from "./config.js";
import { createLogger } from "./logger.js";
import { Tick } from "./tick.js";
import { MarketMonitor } from "./components/MarketMonitor.js";
import { PolicyEvaluator } from "./components/PolicyEvaluator.js";
import { Simulator } from "./components/Simulator.js";
import { ProposalBuilder } from "./components/ProposalBuilder.js";
import { Reporter } from "./components/Reporter.js";

export async function main(): Promise<void> {
  const config = loadConfig(process.env.HELIX_CONFIG_PATH ?? "./config.yaml");
  const log = createLogger(config);

  log.info({ treasury: config.treasury.vault_address }, "Helix agent starting");

  const monitor = new MarketMonitor(config, log);
  const evaluator = new PolicyEvaluator(config, log);
  const simulator = new Simulator(config, log);
  const builder = new ProposalBuilder(config, log);
  const reporter = new Reporter(config, log);

  const tick = new Tick({ monitor, evaluator, simulator, builder, reporter, config, log });

  await monitor.start(); // begins event subscriptions

  // Periodic tick
  const intervalMs = parseTickInterval(config.agent.tick_interval);
  setInterval(() => {
    tick.run().catch((err) => log.error({ err }, "tick failed"));
  }, intervalMs);

  // Event-driven tick
  monitor.on("vaultEvent", () => tick.run().catch((err) => log.error({ err }, "tick failed")));
  monitor.on("priceAlert", () => tick.run().catch((err) => log.error({ err }, "tick failed")));

  log.info({ intervalMs, mode: config.agent.modes }, "agent ready");
}

function parseTickInterval(s: string): number {
  const m = /^(\d+)([smhd])$/.exec(s.trim());
  if (!m) throw new Error(`Invalid tick interval: ${s}`);
  const n = Number(m[1]);
  const unit = m[2];
  return n * { s: 1_000, m: 60_000, h: 3_600_000, d: 86_400_000 }[unit as "s" | "m" | "h" | "d"];
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
