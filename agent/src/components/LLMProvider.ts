/**
 * LLMProvider — abstraction over Anthropic and OpenAI for Helix LLM features.
 *
 * Used for:
 *   1. Natural language → HXP DSL translation
 *   2. Proposal explanation generation
 *   3. Anomaly summarization
 *
 * LLMs are NEVER in the execution path. See docs/03-execution-agent.md §3.5.
 */

import type { Logger } from "pino";
import type { Config } from "../config.js";

export interface LLMResponse {
  content: string;
  model: string;
  tokensUsed: number;
}

export class LLMProvider {
  private readonly config: Config;
  private readonly log: Logger;
  private readonly enabled: boolean;

  constructor(config: Config, log: Logger) {
    this.config = config;
    this.log = log;
    this.enabled = !!config.llm?.provider;
  }

  isEnabled(): boolean {
    return this.enabled;
  }

  /**
   * Translate natural language treasury instructions to HXP DSL format.
   * Output must be reviewed by a human before committing.
   */
  async nlToDsl(naturalLanguage: string): Promise<LLMResponse> {
    if (!this.enabled) {
      throw new Error("LLM not configured");
    }

    const systemPrompt = `You are a Helix Policy DSL (HXP) compiler. Convert natural language treasury management instructions into valid HXP JSON policy format.

The HXP schema requires:
- version: "0.1"
- name: short policy name
- treasury: the treasury address (use placeholder "0x0000000000000000000000000000000000000000" if not specified)
- hard_constraints: array of inviolable rules with kinds: MAX_SINGLE_ALLOCATION, MIN_LIQUIDITY_RATIO, MAX_COUNTERPARTY_EXPOSURE, RUNWAY_FLOOR_DAYS, MAX_DRAWDOWN, MAX_DAILY_MOVEMENT, STABLECOIN_FLOOR_RATIO
- soft_policies: array of optimization goals with kinds: TARGET_ALLOCATION, REBALANCE_BAND, YIELD_OPTIMIZATION, RUNWAY_EXTENSION, PENDLE_YIELD_CURVE, RWA_ALLOCATION

Output valid JSON only. No markdown fences. No explanation.`;

    return this._chat(systemPrompt, naturalLanguage);
  }

  /**
   * Generate a human-readable explanation of a treasury proposal for multisig signers.
   */
  async explainProposal(proposal: {
    policyHash: string;
    actions: Array<{ kind: number; asset: string; amount: string }>;
    preNAV: string;
    postNAV: string;
  }): Promise<LLMResponse> {
    if (!this.enabled) {
      throw new Error("LLM not configured");
    }

    const actionKindNames: Record<number, string> = {
      0: "NOOP", 1: "TRANSFER", 2: "SWAP", 3: "SUPPLY", 4: "WITHDRAW",
      5: "BORROW", 6: "REPAY", 7: "BUY_RWA", 8: "SELL_RWA", 9: "REDEEM_RWA",
      10: "BUY_PT", 11: "SELL_PT", 12: "BUY_YT", 13: "SELL_YT",
      14: "REDEEM_PT_AT_MATURITY", 15: "SET_FLAG",
    };

    const actionDescriptions = proposal.actions.map((a) =>
      `${actionKindNames[a.kind] ?? "UNKNOWN"}: asset=${a.asset}, amount=${a.amount}`
    ).join("\n");

    const systemPrompt = `You are a treasury operations assistant. Generate a clear, concise explanation of a treasury proposal for multisig signers. Be specific about what will happen and why. Keep it under 200 words.`;

    const userPrompt = `Proposal triggered by policy ${proposal.policyHash}.

Actions:
${actionDescriptions}

Pre-execution NAV: ${proposal.preNAV} USDC
Post-execution NAV: ${proposal.postNAV} USDC

Explain what this proposal does and its impact.`;

    return this._chat(systemPrompt, userPrompt);
  }

  /**
   * Summarize a PolicyEngine rejection into actionable feedback.
   */
  async summarizeAnomaly(context: {
    rejectionReason: string;
    policyHash: string;
    constraintViolations: string[];
  }): Promise<LLMResponse> {
    if (!this.enabled) {
      throw new Error("LLM not configured");
    }

    const systemPrompt = `You are a treasury risk analyst. Translate technical PolicyEngine rejection reasons into actionable feedback for treasury operators. Be concise and specific.`;

    const userPrompt = `Policy ${context.policyHash} proposal was rejected.
Reason: ${context.rejectionReason}
Constraint violations: ${context.constraintViolations.join(", ")}

Explain what went wrong and suggest corrective actions.`;

    return this._chat(systemPrompt, userPrompt);
  }

  private async _chat(systemPrompt: string, userMessage: string): Promise<LLMResponse> {
    const provider = this.config.llm!.provider;
    const model = this.config.llm!.model;

    this.log.debug({ provider, model }, "LLM request");

    if (provider === "anthropic") {
      return this._chatAnthropic(systemPrompt, userMessage, model);
    } else if (provider === "openai") {
      return this._chatOpenAI(systemPrompt, userMessage, model);
    } else {
      throw new Error(`Unknown LLM provider: ${provider}`);
    }
  }

  private async _chatAnthropic(system: string, user: string, model: string): Promise<LLMResponse> {
    const { default: Anthropic } = await import("@anthropic-ai/sdk");
    const client = new Anthropic();

    const response = await client.messages.create({
      model,
      max_tokens: 1024,
      system,
      messages: [{ role: "user", content: user }],
    });

    const content = response.content
      .filter((block: any) => block.type === "text")
      .map((block: any) => block.text)
      .join("");

    return {
      content,
      model: response.model,
      tokensUsed: (response.usage?.input_tokens ?? 0) + (response.usage?.output_tokens ?? 0),
    };
  }

  private async _chatOpenAI(system: string, user: string, model: string): Promise<LLMResponse> {
    const { default: OpenAI } = await import("openai");
    const client = new OpenAI();

    const response = await client.chat.completions.create({
      model,
      max_tokens: 1024,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    });

    return {
      content: response.choices[0]?.message?.content ?? "",
      model: response.model,
      tokensUsed: response.usage?.total_tokens ?? 0,
    };
  }
}
