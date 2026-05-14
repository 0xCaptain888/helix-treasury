/** Reporter — surfaces tick outcomes to Discord/Slack/email with LLM-generated summaries. */

import type { Logger } from "pino";
import type { Config } from "../config.js";
import type { ActivePolicy } from "./MarketMonitor.js";
import type { Action } from "./PolicyEvaluator.js";
import type { SimulationResult } from "./Simulator.js";
import type { Proposal } from "./ProposalBuilder.js";
import { LLMProvider } from "./LLMProvider.js";

export class Reporter {
  private readonly llm: LLMProvider;

  constructor(private readonly config: Config, private readonly log: Logger) {
    this.llm = new LLMProvider(config, log);
  }

  async proposed(policy: ActivePolicy, proposal: Proposal, txHash: `0x${string}`): Promise<void> {
    this.log.info({ policyHash: policy.hash, txHash }, "proposal submitted");

    // Generate LLM-powered human-readable summary for notification channels
    let summary = `Proposal submitted for policy ${policy.hash}. Tx: ${txHash}`;
    if (this.llm.isEnabled() && this.config.llm?.enabled_features?.includes("proposal_explanation")) {
      try {
        const response = await this.llm.explainProposal({
          policyHash: policy.hash,
          actions: proposal.actions.map((a) => ({
            kind: a.kind,
            asset: a.asset,
            amount: a.amount.toString(),
          })),
          preNAV: "N/A",
          postNAV: "N/A",
        });
        summary = response.content;
        this.log.debug({ tokensUsed: response.tokensUsed }, "LLM explanation generated");
      } catch (err) {
        this.log.warn({ err }, "LLM explanation failed, using fallback summary");
      }
    }

    await this._notify(summary);
  }

  async draft(policy: ActivePolicy, actions: Action[], _sim: SimulationResult): Promise<void> {
    this.log.info({ policyHash: policy.hash, actions: actions.length }, "draft (monitoring mode)");
  }

  async skip(policy: ActivePolicy, reason: string): Promise<void> {
    this.log.warn({ policyHash: policy.hash, reason }, "policy skipped");

    // Use LLM to generate actionable feedback from skip reason
    if (this.llm.isEnabled() && this.config.llm?.enabled_features?.includes("anomaly_summary")) {
      try {
        const response = await this.llm.summarizeAnomaly({
          rejectionReason: reason,
          policyHash: policy.hash,
          constraintViolations: [reason],
        });
        this.log.info({ summary: response.content }, "anomaly summary");
        await this._notify(`Policy ${policy.hash} skipped: ${response.content}`);
      } catch (err) {
        this.log.warn({ err }, "LLM anomaly summary failed");
      }
    }
  }

  private async _notify(message: string): Promise<void> {
    // Discord webhook
    if (this.config.reporting?.discord_webhook) {
      try {
        await fetch(this.config.reporting.discord_webhook, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ content: message }),
        });
      } catch (err) {
        this.log.warn({ err }, "Discord notification failed");
      }
    }

    // Slack webhook
    if (this.config.reporting?.slack_webhook) {
      try {
        await fetch(this.config.reporting.slack_webhook, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ text: message }),
        });
      } catch (err) {
        this.log.warn({ err }, "Slack notification failed");
      }
    }
  }
}
