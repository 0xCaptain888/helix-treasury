/** ProposalBuilder — assembles and submits the on-chain Proposal. */

import { createWalletClient, createPublicClient, http, type WalletClient, type PublicClient } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { arbitrumSepolia } from "viem/chains";
import type { Logger } from "pino";
import type { Config } from "../config.js";
import type { ActivePolicy, MarketStateSnapshot } from "./MarketMonitor.js";
import type { Action } from "./PolicyEvaluator.js";
import type { SimulationResult } from "./Simulator.js";

export interface Proposal {
  policyHash: `0x${string}`;
  marketStateHash: `0x${string}`;
  actions: Action[];
  dryRunResultHash: `0x${string}`;
  expiresAt: number;
  agentSignature: `0x${string}`;
}

const PROPOSAL_REGISTRY_ABI = [
  { type: "function", name: "submitProposal", inputs: [{ type: "bytes32", name: "policyHash" }, { type: "bytes32", name: "marketStateHash" }, { type: "tuple[]", name: "actions", components: [{ type: "uint8", name: "kind" }, { type: "address", name: "adapter" }, { type: "address", name: "asset" }, { type: "uint256", name: "amount" }, { type: "bytes", name: "params" }] }, { type: "bytes32", name: "dryRunResultHash" }, { type: "bytes", name: "agentSig" }], outputs: [{ type: "bytes32", name: "proposalId" }], stateMutability: "nonpayable" },
] as const;

export class ProposalBuilder {
  private walletClient: WalletClient | null = null;
  private publicClient: PublicClient;

  constructor(private readonly config: Config, private readonly log: Logger) {
    const chainMap: Record<string, any> = {
      "arbitrum-sepolia": arbitrumSepolia,
    };
    this.publicClient = createPublicClient({
      chain: chainMap[config.chain.primary] ?? arbitrumSepolia,
      transport: http(config.chain.rpc_urls[0]),
    });

    // Initialize wallet client if key is available
    if (config.agent.key_source === "env" && process.env.AGENT_PRIVATE_KEY) {
      const account = privateKeyToAccount(process.env.AGENT_PRIVATE_KEY as `0x${string}`);
      this.walletClient = createWalletClient({
        account,
        chain: chainMap[config.chain.primary] ?? arbitrumSepolia,
        transport: http(config.chain.rpc_urls[0]),
      });
    }
  }

  build(
    policy: ActivePolicy,
    actions: Action[],
    market: MarketStateSnapshot,
    sim: SimulationResult,
  ): Proposal {
    const PROPOSAL_TTL = 7 * 24 * 60 * 60; // 7 days in seconds
    const now = Math.floor(Date.now() / 1000);

    return {
      policyHash: policy.hash,
      marketStateHash: market.marketHash,
      actions,
      dryRunResultHash: sim.resultHash,
      expiresAt: now + PROPOSAL_TTL,
      agentSignature: "0x" as `0x${string}`, // Signed during submit
    };
  }

  async submit(p: Proposal): Promise<`0x${string}`> {
    if (!this.walletClient?.account) {
      throw new Error("Wallet client not configured — set AGENT_PRIVATE_KEY env var");
    }

    const registryAddr = this.config.treasury.proposal_registry as `0x${string}`;

    // Sign the proposal data
    const proposalData = JSON.stringify({
      policyHash: p.policyHash,
      marketStateHash: p.marketStateHash,
      dryRunResultHash: p.dryRunResultHash,
      expiresAt: p.expiresAt,
    });
    const signature = await this.walletClient.account.signMessage({
      message: proposalData,
    });

    // Submit on-chain
    const hash = await this.walletClient.writeContract({
      address: registryAddr,
      abi: PROPOSAL_REGISTRY_ABI,
      functionName: "submitProposal",
      args: [
        p.policyHash,
        p.marketStateHash,
        p.actions.map((a) => ({
          kind: a.kind,
          adapter: a.adapter,
          asset: a.asset,
          amount: a.amount,
          params: a.params,
        })),
        p.dryRunResultHash,
        signature,
      ],
    });

    this.log.info({ txHash: hash, policyHash: p.policyHash }, "proposal submitted on-chain");
    return hash;
  }
}
