/** Simulator — runs candidate actions against forked state via eth_call with overrides. */

import { createPublicClient, http, type PublicClient } from "viem";
import { arbitrumSepolia } from "viem/chains";
import type { Logger } from "pino";
import type { Config } from "../config.js";
import type { Action } from "./PolicyEvaluator.js";
import type { TreasuryStateSnapshot, MarketStateSnapshot } from "./MarketMonitor.js";

export interface SimulationResult {
  postState: TreasuryStateSnapshot;
  violations: string[];
  resultHash: `0x${string}`;
}

const ADAPTER_ABI = [
  { type: "function", name: "simulate", inputs: [{ type: "tuple", name: "a", components: [{ type: "uint8", name: "kind" }, { type: "address", name: "adapter" }, { type: "address", name: "asset" }, { type: "uint256", name: "amount" }, { type: "bytes", name: "params" }] }, { type: "tuple", name: "pre", components: [{ type: "address[]", name: "assets" }, { type: "uint256[]", name: "balances" }, { type: "uint256", name: "totalNAVUsdc" }, { type: "uint64", name: "snapshotAt" }, { type: "bytes32", name: "stateHash" }] }], outputs: [{ type: "tuple", components: [{ type: "address[]", name: "assets" }, { type: "uint256[]", name: "balances" }, { type: "uint256", name: "totalNAVUsdc" }, { type: "uint64", name: "snapshotAt" }, { type: "bytes32", name: "stateHash" }] }], stateMutability: "view" },
] as const;

export class Simulator {
  private client: PublicClient;

  constructor(private readonly config: Config, private readonly log: Logger) {
    const chainMap: Record<string, any> = {
      "arbitrum-sepolia": arbitrumSepolia,
    };
    this.client = createPublicClient({
      chain: chainMap[config.chain.primary] ?? arbitrumSepolia,
      transport: http(config.chain.rpc_urls[0]),
    });
  }

  async run(
    pre: TreasuryStateSnapshot,
    actions: Action[],
    _market: MarketStateSnapshot,
  ): Promise<SimulationResult> {
    this.log.info({ actionCount: actions.length }, "simulation starting");

    let currentState = pre;
    const violations: string[] = [];

    for (const action of actions) {
      try {
        // Call adapter.simulate() via eth_call to project post-state
        const result = await this.client.readContract({
          address: action.adapter,
          abi: ADAPTER_ABI,
          functionName: "simulate",
          args: [
            {
              kind: action.kind,
              adapter: action.adapter,
              asset: action.asset,
              amount: action.amount,
              params: action.params,
            },
            {
              assets: currentState.assets,
              balances: currentState.balances,
              totalNAVUsdc: currentState.totalNAVUsdc,
              snapshotAt: BigInt(currentState.snapshotAt),
              stateHash: currentState.stateHash,
            },
          ],
        }) as any;

        currentState = {
          assets: result.assets,
          balances: result.balances,
          totalNAVUsdc: result.totalNAVUsdc,
          snapshotAt: Number(result.snapshotAt),
          stateHash: result.stateHash,
        };
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : String(err);
        this.log.warn({ action: action.kind, err: errMsg }, "simulation step failed");
        violations.push(`Action ${action.kind} on ${action.asset} failed: ${errMsg}`);
      }
    }

    // Compute result hash
    const hashInput = JSON.stringify({
      assets: currentState.assets,
      balances: currentState.balances.map(String),
      nav: currentState.totalNAVUsdc.toString(),
    });
    const resultHash = `0x${Buffer.from(hashInput).toString("hex").slice(0, 64).padEnd(64, "0")}` as `0x${string}`;

    this.log.info({ violations: violations.length, postNAV: currentState.totalNAVUsdc.toString() }, "simulation complete");

    return {
      postState: currentState,
      violations,
      resultHash,
    };
  }
}
