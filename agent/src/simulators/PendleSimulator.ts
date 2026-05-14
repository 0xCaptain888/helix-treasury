/**
 * PendleSimulator — simulates Pendle PT/YT buy/sell/redeem actions.
 *
 * See docs/07-integrations.md §3.
 */

export interface PendlePosition {
  ptToken: `0x${string}`;
  ytToken: `0x${string}`;
  market: `0x${string}`;
  ptBalance: bigint;
  ytBalance: bigint;
  maturity: number; // unix timestamp
  impliedApy: number; // in basis points
}

export interface PendleSimulationInput {
  actionKind: "BUY_PT" | "SELL_PT" | "BUY_YT" | "SELL_YT" | "REDEEM_PT_AT_MATURITY";
  amount: bigint;
  currentPosition: PendlePosition;
  underlyingPrice: bigint; // USDC-6
}

export interface PendleSimulationResult {
  postPosition: PendlePosition;
  estimatedValueUsdc: bigint;
  daysToMaturity: number;
  warnings: string[];
}

export class PendleSimulator {
  async simulate(input: PendleSimulationInput): Promise<PendleSimulationResult> {
    const warnings: string[] = [];
    const post = { ...input.currentPosition };
    const now = Math.floor(Date.now() / 1000);
    const daysToMaturity = Math.max(0, Math.floor((post.maturity - now) / 86400));

    switch (input.actionKind) {
      case "BUY_PT":
        post.ptBalance += input.amount;
        if (daysToMaturity < 30) {
          warnings.push("PT maturity is within 30 days — limited yield capture");
        }
        break;

      case "SELL_PT":
        if (input.amount > post.ptBalance) {
          warnings.push("Sell amount exceeds PT balance");
        }
        post.ptBalance -= input.amount > post.ptBalance ? post.ptBalance : input.amount;
        break;

      case "BUY_YT":
        post.ytBalance += input.amount;
        warnings.push("YT positions are speculative — ensure policy allows YT exposure");
        if (daysToMaturity < 14) {
          warnings.push("YT near maturity — value approaches zero rapidly");
        }
        break;

      case "SELL_YT":
        if (input.amount > post.ytBalance) {
          warnings.push("Sell amount exceeds YT balance");
        }
        post.ytBalance -= input.amount > post.ytBalance ? post.ytBalance : input.amount;
        break;

      case "REDEEM_PT_AT_MATURITY":
        if (now < post.maturity) {
          warnings.push("PT has not matured yet — redemption will fail on-chain");
        }
        post.ptBalance -= input.amount > post.ptBalance ? post.ptBalance : input.amount;
        break;
    }

    // Estimate value (simplified: PT value approaches face value at maturity)
    const ptDiscount = daysToMaturity > 0
      ? BigInt(Math.floor((post.impliedApy * daysToMaturity) / 36500))
      : 0n;
    const ptValuePerUnit = input.underlyingPrice - (input.underlyingPrice * ptDiscount / 10000n);
    const estimatedValueUsdc = (post.ptBalance * ptValuePerUnit / (10n ** 18n))
      + (post.ytBalance * input.underlyingPrice * BigInt(Math.min(daysToMaturity, 365)) / (365n * 10n ** 18n));

    return {
      postPosition: post,
      estimatedValueUsdc,
      daysToMaturity,
      warnings,
    };
  }
}
