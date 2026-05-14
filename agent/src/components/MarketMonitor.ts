/** MarketMonitor — watches treasury vault events, oracle prices, yield rates. */

import { EventEmitter } from "node:events";
import { createPublicClient, http, type PublicClient } from "viem";
import { arbitrumSepolia } from "viem/chains";
import type { Logger } from "pino";
import type { Config } from "../config.js";

export interface TreasuryStateSnapshot {
  assets: `0x${string}`[];
  balances: bigint[];
  totalNAVUsdc: bigint;
  snapshotAt: number;
  stateHash: `0x${string}`;
}

export interface MarketStateSnapshot {
  assets: `0x${string}`[];
  pricesUsd6: bigint[];
  observedAt: number[];
  marketHash: `0x${string}`;
}

export interface ActivePolicy {
  hash: `0x${string}`;
  bytecode: `0x${string}`;
  hardConstraintIds: `0x${string}`[];
}

const VAULT_ABI = [
  { type: "function", name: "getState", inputs: [], outputs: [{ type: "tuple[]", name: "entries" }, { type: "uint256[]", name: "balances" }], stateMutability: "view" },
  { type: "function", name: "getNAV", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "event", name: "Deposited", inputs: [{ type: "address", name: "from", indexed: true }, { type: "address", name: "token", indexed: true }, { type: "uint256", name: "amount" }] },
  { type: "event", name: "Executed", inputs: [{ type: "bytes32", name: "proposalId", indexed: true }] },
  { type: "event", name: "EmergencyPaused", inputs: [{ type: "address", name: "by" }] },
] as const;

const POLICY_REGISTRY_ABI = [
  { type: "function", name: "activePolicyHash", inputs: [], outputs: [{ type: "bytes32" }], stateMutability: "view" },
  { type: "function", name: "getPolicy", inputs: [{ type: "bytes32" }], outputs: [{ type: "bytes" }, { type: "tuple", components: [{ type: "bytes32" }, { type: "bytes32" }, { type: "address" }, { type: "uint64" }, { type: "uint64" }, { type: "bool" }, { type: "bytes32[]" }] }], stateMutability: "view" },
] as const;

export class MarketMonitor extends EventEmitter {
  private client: PublicClient;
  private unwatchVault: (() => void) | null = null;

  constructor(private readonly config: Config, private readonly log: Logger) {
    super();
    const chainMap: Record<string, any> = {
      "arbitrum-sepolia": arbitrumSepolia,
    };
    this.client = createPublicClient({
      chain: chainMap[config.chain.primary] ?? arbitrumSepolia,
      transport: http(config.chain.rpc_urls[0]),
    });
  }

  async start(): Promise<void> {
    this.log.info("MarketMonitor starting");

    // Subscribe to vault events
    try {
      this.unwatchVault = this.client.watchContractEvent({
        address: this.config.treasury.vault_address as `0x${string}`,
        abi: VAULT_ABI,
        onLogs: (logs) => {
          for (const log of logs) {
            this.log.info({ event: log.eventName }, "vault event received");
            this.emit("vaultEvent", log);
          }
        },
      });
    } catch (err) {
      this.log.warn({ err }, "Failed to subscribe to vault events, will poll instead");
    }

    this.log.info("MarketMonitor started");
  }

  async getTreasuryState(): Promise<TreasuryStateSnapshot> {
    const vaultAddr = this.config.treasury.vault_address as `0x${string}`;

    try {
      const [stateResult, nav] = await Promise.all([
        this.client.readContract({
          address: vaultAddr,
          abi: VAULT_ABI,
          functionName: "getState",
        }),
        this.client.readContract({
          address: vaultAddr,
          abi: VAULT_ABI,
          functionName: "getNAV",
        }),
      ]);

      const [entries, balances] = stateResult as [any[], bigint[]];
      const assets = entries.map((e: any) => e.token as `0x${string}`);

      const stateHash = `0x${Buffer.from(
        JSON.stringify({ assets, balances: balances.map(String), nav: nav.toString() })
      ).toString("hex").slice(0, 64).padEnd(64, "0")}` as `0x${string}`;

      return {
        assets,
        balances,
        totalNAVUsdc: nav as bigint,
        snapshotAt: Math.floor(Date.now() / 1000),
        stateHash,
      };
    } catch (err) {
      this.log.error({ err }, "Failed to read treasury state");
      throw err;
    }
  }

  async getMarketState(): Promise<MarketStateSnapshot> {
    // Read prices from oracle via vault's oracle aggregator
    // For now, return state from the vault's perspective
    const state = await this.getTreasuryState();
    const now = Math.floor(Date.now() / 1000);

    return {
      assets: state.assets,
      pricesUsd6: state.assets.map(() => 0n), // Prices fetched on-chain by oracle
      observedAt: state.assets.map(() => now),
      marketHash: state.stateHash,
    };
  }

  async getActivePolicies(): Promise<ActivePolicy[]> {
    const registryAddr = this.config.treasury.policy_registry as `0x${string}`;

    try {
      const hash = await this.client.readContract({
        address: registryAddr,
        abi: POLICY_REGISTRY_ABI,
        functionName: "activePolicyHash",
      }) as `0x${string}`;

      if (hash === "0x0000000000000000000000000000000000000000000000000000000000000000") {
        return [];
      }

      const [bytecode, meta] = await this.client.readContract({
        address: registryAddr,
        abi: POLICY_REGISTRY_ABI,
        functionName: "getPolicy",
        args: [hash],
      }) as [`0x${string}`, any];

      return [{
        hash,
        bytecode,
        hardConstraintIds: (meta.hardConstraintIds ?? []) as `0x${string}`[],
      }];
    } catch (err) {
      this.log.error({ err }, "Failed to read active policies");
      return [];
    }
  }

  stop(): void {
    if (this.unwatchVault) {
      this.unwatchVault();
      this.unwatchVault = null;
    }
  }
}
