import { readFileSync } from "node:fs";
import { parse } from "yaml";
import { z } from "zod";

const ConfigSchema = z.object({
  treasury: z.object({
    vault_address: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
    policy_registry: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
    proposal_registry: z.string().regex(/^0x[a-fA-F0-9]{40}$/),
  }),
  chain: z.object({
    primary: z.enum(["arbitrum-sepolia", "robinhood-testnet", "arbitrum-one"]),
    rpc_urls: z.array(z.string().url()).min(1),
    fallback_rpc: z.array(z.string().url()).default([]),
  }),
  agent: z.object({
    key_source: z.enum(["env", "aws-kms", "gcp-kms", "hashicorp-vault"]),
    tick_interval: z.string().default("4h"),
    modes: z.array(z.enum(["monitoring", "proposing", "emergency"])).default(["monitoring"]),
  }),
  llm: z
    .object({
      provider: z.enum(["anthropic", "openai"]),
      model: z.string(),
      enabled_features: z.array(z.enum(["proposal_explanation", "nl_to_dsl", "anomaly_summary"])).default([]),
    })
    .optional(),
  oracles: z.object({
    primary: z.enum(["chainlink", "pyth", "robinhood"]),
    secondary: z.enum(["chainlink", "pyth", "robinhood"]).optional(),
    max_staleness: z.string().default("30m"),
  }),
  reporting: z
    .object({
      discord_webhook: z.string().url().optional(),
      slack_webhook: z.string().url().optional(),
      email: z.string().email().optional(),
    })
    .default({}),
});

export type Config = z.infer<typeof ConfigSchema>;

export function loadConfig(path: string): Config {
  const raw = readFileSync(path, "utf8");
  return ConfigSchema.parse(parse(raw));
}
