#!/usr/bin/env tsx
/**
 * verify-deployment.ts — Post-deployment verification script.
 *
 * Checks that all Helix contracts are deployed correctly, wired together,
 * and responding to basic queries.
 *
 * Usage:
 *   pnpm verify:deployment --network arbitrum-sepolia
 *
 * See docs/06-deployment.md §7.
 */

import { createPublicClient, http, type Address } from "viem";
import { arbitrumSepolia } from "viem/chains";
import { readFileSync, existsSync } from "node:fs";

// Minimal ABIs for verification
const VAULT_ABI = [
  { type: "function", name: "getNAV", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "safe", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "guardian", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "paused", inputs: [], outputs: [{ type: "bool" }], stateMutability: "view" },
  { type: "function", name: "engine", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "taxEngine", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "oracleAggregator", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
] as const;

const PROPOSAL_REGISTRY_ABI = [
  { type: "function", name: "executionTimelock", inputs: [], outputs: [{ type: "uint64" }], stateMutability: "view" },
  { type: "function", name: "engine", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "vault", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
  { type: "function", name: "isAuthorizedAgent", inputs: [{ type: "address" }], outputs: [{ type: "bool" }], stateMutability: "view" },
] as const;

const POLICY_REGISTRY_ABI = [
  { type: "function", name: "activePolicyHash", inputs: [], outputs: [{ type: "bytes32" }], stateMutability: "view" },
  { type: "function", name: "owner", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
] as const;

const ORACLE_ABI = [
  { type: "function", name: "maxStaleness", inputs: [], outputs: [{ type: "uint32" }], stateMutability: "view" },
  { type: "function", name: "minSources", inputs: [], outputs: [{ type: "uint8" }], stateMutability: "view" },
  { type: "function", name: "safe", inputs: [], outputs: [{ type: "address" }], stateMutability: "view" },
] as const;

const TAX_ENGINE_ABI = [
  { type: "function", name: "jurisdiction", inputs: [], outputs: [{ type: "bytes8" }], stateMutability: "view" },
  { type: "function", name: "lotMethod", inputs: [], outputs: [{ type: "uint8" }], stateMutability: "view" },
] as const;

interface DeploymentAddresses {
  oracle_aggregator: Address;
  policy_engine: Address;
  policy_registry: Address;
  proposal_registry: Address;
  treasury_vault: Address;
  tax_engine: Address;
  treasury_factory: Address;
}

async function main() {
  const args = process.argv.slice(2);
  const networkFlag = args.indexOf("--network");
  const network = networkFlag >= 0 ? args[networkFlag + 1] : "arbitrum-sepolia";

  console.log(`\n=== Helix Deployment Verification ===`);
  console.log(`Network: ${network}\n`);

  // Load deployment addresses
  const phase3Path = "./deployments/phase3.json";
  if (!existsSync(phase3Path)) {
    console.error(`ERROR: ${phase3Path} not found. Run deployment scripts first.`);
    process.exit(1);
  }

  const addresses: DeploymentAddresses = JSON.parse(readFileSync(phase3Path, "utf-8"));
  const rpcUrl = process.env.ARB_SEPOLIA_RPC ?? "https://sepolia-rollup.arbitrum.io/rpc";

  const client = createPublicClient({
    chain: arbitrumSepolia,
    transport: http(rpcUrl),
  });

  let passed = 0;
  let failed = 0;

  async function check(name: string, fn: () => Promise<boolean>): Promise<void> {
    try {
      const ok = await fn();
      if (ok) {
        console.log(`  PASS  ${name}`);
        passed++;
      } else {
        console.log(`  FAIL  ${name}`);
        failed++;
      }
    } catch (err) {
      console.log(`  FAIL  ${name} — ${err instanceof Error ? err.message : String(err)}`);
      failed++;
    }
  }

  // 1. Contract deployment checks
  console.log("1. Contract Deployment");
  for (const [name, addr] of Object.entries(addresses)) {
    await check(`${name} has code at ${addr}`, async () => {
      const code = await client.getCode({ address: addr as Address });
      return !!code && code !== "0x";
    });
  }

  // 2. TreasuryVault checks
  console.log("\n2. TreasuryVault");
  await check("Vault.safe is non-zero", async () => {
    const safe = await client.readContract({ address: addresses.treasury_vault, abi: VAULT_ABI, functionName: "safe" });
    return safe !== "0x0000000000000000000000000000000000000000";
  });
  await check("Vault.getNAV returns 0 (empty treasury)", async () => {
    const nav = await client.readContract({ address: addresses.treasury_vault, abi: VAULT_ABI, functionName: "getNAV" });
    return nav === 0n;
  });
  await check("Vault is not paused", async () => {
    const paused = await client.readContract({ address: addresses.treasury_vault, abi: VAULT_ABI, functionName: "paused" });
    return !paused;
  });
  await check("Vault.engine matches policy_engine", async () => {
    const engine = await client.readContract({ address: addresses.treasury_vault, abi: VAULT_ABI, functionName: "engine" });
    return (engine as string).toLowerCase() === addresses.policy_engine.toLowerCase();
  });
  await check("Vault.taxEngine matches tax_engine", async () => {
    const tax = await client.readContract({ address: addresses.treasury_vault, abi: VAULT_ABI, functionName: "taxEngine" });
    return (tax as string).toLowerCase() === addresses.tax_engine.toLowerCase();
  });

  // 3. ProposalRegistry checks
  console.log("\n3. ProposalRegistry");
  await check("ProposalRegistry.executionTimelock is 24 hours", async () => {
    const timelock = await client.readContract({ address: addresses.proposal_registry, abi: PROPOSAL_REGISTRY_ABI, functionName: "executionTimelock" });
    return timelock === 86400n; // 24 hours in seconds
  });
  await check("ProposalRegistry.engine matches policy_engine", async () => {
    const engine = await client.readContract({ address: addresses.proposal_registry, abi: PROPOSAL_REGISTRY_ABI, functionName: "engine" });
    return (engine as string).toLowerCase() === addresses.policy_engine.toLowerCase();
  });

  // 4. PolicyRegistry checks
  console.log("\n4. PolicyRegistry");
  await check("PolicyRegistry.activePolicyHash is non-zero", async () => {
    const hash = await client.readContract({ address: addresses.policy_registry, abi: POLICY_REGISTRY_ABI, functionName: "activePolicyHash" });
    return hash !== "0x0000000000000000000000000000000000000000000000000000000000000000";
  });

  // 5. OracleAggregator checks
  console.log("\n5. OracleAggregator");
  await check("OracleAggregator.maxStaleness is set", async () => {
    const staleness = await client.readContract({ address: addresses.oracle_aggregator, abi: ORACLE_ABI, functionName: "maxStaleness" });
    return staleness > 0;
  });
  await check("OracleAggregator.minSources >= 1", async () => {
    const sources = await client.readContract({ address: addresses.oracle_aggregator, abi: ORACLE_ABI, functionName: "minSources" });
    return sources >= 1;
  });

  // 6. TaxEngine checks
  console.log("\n6. TaxEngine");
  await check("TaxEngine.lotMethod is valid (0-2)", async () => {
    const method = await client.readContract({ address: addresses.tax_engine, abi: TAX_ENGINE_ABI, functionName: "lotMethod" });
    return method <= 2;
  });

  // Summary
  console.log(`\n=== Results: ${passed} passed, ${failed} failed ===`);
  if (failed > 0) {
    console.log("\nDeployment verification FAILED. Review the failures above.");
    process.exit(1);
  } else {
    console.log("\nDeployment verification PASSED. All checks OK.");
  }
}

main().catch((err) => {
  console.error("Verification failed:", err);
  process.exit(1);
});
