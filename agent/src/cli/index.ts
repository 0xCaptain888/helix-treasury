#!/usr/bin/env node

/**
 * Helix CLI — command-line interface for treasury operators.
 * Provides commands for agent management, policy operations, and LLM-powered DSL generation.
 */

import { Command } from "commander";
import { loadConfig } from "../config.js";
import { createLogger } from "../logger.js";
import { LLMProvider } from "../components/LLMProvider.js";

const program = new Command();

program
  .name("helix-cli")
  .description("Helix Treasury CLI — manage your programmable treasury")
  .version("0.5.0-alpha");

program
  .command("policy:from-nl")
  .description("Convert natural language treasury instructions to HXP policy DSL")
  .argument("<instruction>", "Natural language description of the policy")
  .option("--config <path>", "Path to config file", "./config.yaml")
  .action(async (instruction: string, opts: { config: string }) => {
    const config = loadConfig(opts.config);
    const log = createLogger(config);
    const llm = new LLMProvider(config, log);

    if (!llm.isEnabled()) {
      console.error("Error: LLM not configured. Set llm.provider in config.yaml");
      process.exit(1);
    }

    console.log("Translating to HXP DSL...\n");
    const response = await llm.nlToDsl(instruction);
    console.log("Generated HXP Policy:");
    console.log("─".repeat(60));
    console.log(response.content);
    console.log("─".repeat(60));
    console.log(`\nModel: ${response.model} | Tokens: ${response.tokensUsed}`);
    console.log("\n⚠ Review this policy before committing to PolicyRegistry.");
  });

program
  .command("agent:tick")
  .description("Trigger a single agent tick manually")
  .option("--config <path>", "Path to config file", "./config.yaml")
  .action(async (opts: { config: string }) => {
    const { main } = await import("../index.js");
    process.env.HELIX_CONFIG_PATH = opts.config;
    // Trigger single tick
    console.log("Triggering manual tick...");
    await main();
  });

program
  .command("agent:status")
  .description("Show agent and treasury status")
  .option("--config <path>", "Path to config file", "./config.yaml")
  .action(async (opts: { config: string }) => {
    const config = loadConfig(opts.config);
    console.log("Treasury Configuration:");
    console.log(`  Vault:    ${config.treasury.vault_address}`);
    console.log(`  Policy:   ${config.treasury.policy_registry}`);
    console.log(`  Proposal: ${config.treasury.proposal_registry}`);
    console.log(`  Chain:    ${config.chain.primary}`);
    console.log(`  Mode:     ${config.agent.modes.join(", ")}`);
    console.log(`  Tick:     ${config.agent.tick_interval}`);
    if (config.llm) {
      console.log(`  LLM:      ${config.llm.provider}/${config.llm.model}`);
      console.log(`  Features: ${config.llm.enabled_features.join(", ")}`);
    } else {
      console.log(`  LLM:      not configured`);
    }
  });

program.parse();
