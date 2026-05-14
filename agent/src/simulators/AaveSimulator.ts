/**
 * AaveSimulator — simulates Aave V3 supply/withdraw/borrow/repay actions
 * against current reserve data to predict post-state.
 *
 * See docs/07-integrations.md §2.
 */

import { createPublicClient, http, type PublicClient } from "viem";
import { arbitrumSepolia } from "viem/chains";

export interface AavePosition {
  asset: `0x${string}`;
  supplied: bigint;
  borrowed: bigint;
  aTokenBalance: bigint;
  supplyRate: bigint; // ray (27 decimals)
  borrowRate: bigint; // ray
  healthFactor: bigint;
}

export interface AaveSimulationInput {
  actionKind: "SUPPLY" | "WITHDRAW" | "BORROW" | "REPAY";
  asset: `0x${string}`;
  amount: bigint;
  currentPosition: AavePosition;
}

export interface AaveSimulationResult {
  postPosition: AavePosition;
  estimatedApy: number;
  healthFactorChange: bigint;
  warnings: string[];
}

const AAVE_POOL_ABI = [
  { type: "function", name: "getReserveData", inputs: [{ type: "address" }], outputs: [{ type: "tuple", components: [{ type: "uint256" }, { type: "uint128" }, { type: "uint128" }, { type: "uint128" }, { type: "uint128" }, { type: "uint128" }, { type: "uint40" }, { type: "uint16" }, { type: "address" }, { type: "address" }, { type: "address" }, { type: "address" }, { type: "uint128" }, { type: "uint128" }, { type: "uint128" }] }], stateMutability: "view" },
] as const;

export class AaveSimulator {
  private client: PublicClient;

  constructor(rpcUrl: string) {
    this.client = createPublicClient({
      chain: arbitrumSepolia,
      transport: http(rpcUrl),
    });
  }

  async simulate(input: AaveSimulationInput): Promise<AaveSimulationResult> {
    const warnings: string[] = [];
    const post = { ...input.currentPosition };

    switch (input.actionKind) {
      case "SUPPLY":
        post.supplied += input.amount;
        post.aTokenBalance += input.amount;
        break;
      case "WITHDRAW":
        if (input.amount > post.supplied) {
          warnings.push("Withdraw amount exceeds supplied balance");
        }
        post.supplied -= input.amount > post.supplied ? post.supplied : input.amount;
        post.aTokenBalance -= input.amount > post.aTokenBalance ? post.aTokenBalance : input.amount;
        break;
      case "BORROW":
        post.borrowed += input.amount;
        warnings.push("Borrow actions are rare in treasury use — review carefully");
        break;
      case "REPAY":
        post.borrowed -= input.amount > post.borrowed ? post.borrowed : input.amount;
        break;
    }

    // Estimate health factor (simplified)
    const healthFactorChange = post.healthFactor - input.currentPosition.healthFactor;

    // Rate anomaly check
    if (post.supplyRate > input.currentPosition.supplyRate * 11n / 10n) {
      warnings.push("Supply rate jumped >10% — potential anomaly");
    }

    return {
      postPosition: post,
      estimatedApy: Number(post.supplyRate) / 1e25, // Rough conversion from ray
      healthFactorChange,
      warnings,
    };
  }
}
