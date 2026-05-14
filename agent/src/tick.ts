/**
 * Tick — one iteration of the agent's observe / evaluate / simulate / propose loop.
 *
 * Reference implementation matching docs/03-execution-agent.md §4.
 */

import type { Logger } from "pino";
import type { Config } from "./config.js";
import type { MarketMonitor } from "./components/MarketMonitor.js";
import type { PolicyEvaluator } from "./components/PolicyEvaluator.js";
import type { Simulator } from "./components/Simulator.js";
import type { ProposalBuilder } from "./components/ProposalBuilder.js";
import type { Reporter } from "./components/Reporter.js";

export interface TickDeps {
  monitor: MarketMonitor;
  evaluator: PolicyEvaluator;
  simulator: Simulator;
  builder: ProposalBuilder;
  reporter: Reporter;
  config: Config;
  log: Logger;
}

export class Tick {
  private running = false;

  constructor(private readonly deps: TickDeps) {}

  async run(): Promise<void> {
    if (this.running) {
      this.deps.log.debug("tick already running, skipping");
      return;
    }
    this.running = true;
    const tickId = crypto.randomUUID();
    const t0 = Date.now();

    try {
      const state = await this.deps.monitor.getTreasuryState();
      const market = await this.deps.monitor.getMarketState();
      const policies = await this.deps.monitor.getActivePolicies();

      this.deps.log.info({ tickId, policies: policies.length }, "tick start");

      for (const policy of policies) {
        const trigger = await this.deps.evaluator.evaluate(state, market, policy);
        if (trigger.kind === "no-trigger") continue;
        if (trigger.kind === "violation") {
          await this.deps.reporter.skip(policy, trigger.reason);
          continue;
        }

        let actions = trigger.actions;
        let sim = await this.deps.simulator.run(state, actions, market);

        if (sim.violations.length > 0) {
          // TODO(mulerun): attempt repair-plan; if cannot repair, skip
          const repaired = await this.deps.evaluator.repair(state, market, policy, sim.violations);
          if (!repaired) {
            await this.deps.reporter.skip(policy, "cannot repair to satisfy hard constraints");
            continue;
          }
          actions = repaired.actions;
          sim = await this.deps.simulator.run(state, actions, market);
        }

        if (this.deps.config.agent.modes.includes("monitoring") && !this.deps.config.agent.modes.includes("proposing")) {
          // monitoring mode: only draft, don't submit
          await this.deps.reporter.draft(policy, actions, sim);
          continue;
        }

        const proposal = this.deps.builder.build(policy, actions, market, sim);
        const txHash = await this.deps.builder.submit(proposal);
        await this.deps.reporter.proposed(policy, proposal, txHash);
      }

      this.deps.log.info({ tickId, ms: Date.now() - t0 }, "tick complete");
    } finally {
      this.running = false;
    }
  }
}
