/**
 * SafeTxBuilder — builds correctly-formatted Safe transactions for Helix proposals.
 *
 * Creates Safe-compatible transaction data that can be submitted via the Safe Transaction
 * Service API or executed directly through the Safe SDK.
 *
 * See docs/07-integrations.md §1.3.
 */

import type { Address } from "viem";

export interface SafeTransaction {
  to: Address;
  value: string;
  data: `0x${string}`;
  operation: 0 | 1; // 0 = Call, 1 = DelegateCall
  safeTxGas: string;
  baseGas: string;
  gasPrice: string;
  gasToken: Address;
  refundReceiver: Address;
  nonce: number;
}

export interface ProposalContext {
  proposalId: `0x${string}`;
  policyHash: `0x${string}`;
  dryRunResultHash: `0x${string}`;
  actions: Array<{
    kind: number;
    asset: Address;
    amount: bigint;
    description: string;
  }>;
  rationale: string;
}

const APPROVE_SELECTOR = "0x0b1b39c0"; // approveProposal(bytes32)

export class SafeTxBuilder {
  private readonly proposalRegistryAddress: Address;

  constructor(proposalRegistryAddress: Address) {
    this.proposalRegistryAddress = proposalRegistryAddress;
  }

  /**
   * Build a Safe transaction that approves a Helix proposal.
   * The resulting transaction can be submitted to the Safe Transaction Service.
   */
  buildApprovalTx(proposalId: `0x${string}`, nonce: number): SafeTransaction {
    // Encode approveProposal(bytes32 proposalId)
    const data = `${APPROVE_SELECTOR}${proposalId.slice(2)}` as `0x${string}`;

    return {
      to: this.proposalRegistryAddress,
      value: "0",
      data,
      operation: 0, // Call
      safeTxGas: "0",
      baseGas: "0",
      gasPrice: "0",
      gasToken: "0x0000000000000000000000000000000000000000" as Address,
      refundReceiver: "0x0000000000000000000000000000000000000000" as Address,
      nonce,
    };
  }

  /**
   * Generate metadata for the Safe Transaction Service.
   * This metadata is displayed in the Safe UI alongside the transaction.
   */
  generateMetadata(ctx: ProposalContext): Record<string, unknown> {
    return {
      helix: {
        type: "proposal_approval",
        proposalId: ctx.proposalId,
        policyHash: ctx.policyHash,
        dryRunResultHash: ctx.dryRunResultHash,
        actionSummary: ctx.actions.map((a) => ({
          kind: a.kind,
          asset: a.asset,
          amount: a.amount.toString(),
          description: a.description,
        })),
        rationale: ctx.rationale,
      },
    };
  }
}
