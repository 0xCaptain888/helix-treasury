/**
 * RobinhoodSimulator — simulates RWA buy/sell/redeem actions on Robinhood Chain.
 *
 * See docs/07-integrations.md §4.
 */

export interface RWAPosition {
  asset: `0x${string}`;
  balance: bigint;
  costBasisUsdc: bigint;
  currentPriceUsdc: bigint;
  isListed: boolean;
  assetType: "equity" | "etf" | "treasury" | "private_equity";
}

export interface RWASimulationInput {
  actionKind: "BUY_RWA" | "SELL_RWA" | "REDEEM_RWA";
  asset: `0x${string}`;
  amount: bigint;
  currentPosition: RWAPosition;
  priceUsdc: bigint;
}

export interface RWASimulationResult {
  postPosition: RWAPosition;
  realizedPnL: bigint; // positive = gain, negative = loss
  taxImplication: "REALIZED_GAIN" | "REALIZED_LOSS" | "NO_TAX_EVENT";
  warnings: string[];
}

export class RobinhoodSimulator {
  async simulate(input: RWASimulationInput): Promise<RWASimulationResult> {
    const warnings: string[] = [];
    const post = { ...input.currentPosition };
    let realizedPnL = 0n;
    let taxImplication: RWASimulationResult["taxImplication"] = "NO_TAX_EVENT";

    switch (input.actionKind) {
      case "BUY_RWA": {
        if (!post.isListed) {
          warnings.push("Asset is not currently listed — buy may fail on-chain");
        }
        const costOfPurchase = (input.amount * input.priceUsdc) / (10n ** 18n);
        post.balance += input.amount;
        post.costBasisUsdc += costOfPurchase;
        break;
      }

      case "SELL_RWA": {
        if (input.amount > post.balance) {
          warnings.push("Sell amount exceeds position balance");
        }
        const sellAmount = input.amount > post.balance ? post.balance : input.amount;
        const proceeds = (sellAmount * input.priceUsdc) / (10n ** 18n);
        const proportionalCost = post.balance > 0n
          ? (post.costBasisUsdc * sellAmount) / post.balance
          : 0n;

        realizedPnL = proceeds - proportionalCost;
        taxImplication = realizedPnL > 0n ? "REALIZED_GAIN" : realizedPnL < 0n ? "REALIZED_LOSS" : "NO_TAX_EVENT";

        post.balance -= sellAmount;
        post.costBasisUsdc -= proportionalCost;
        break;
      }

      case "REDEEM_RWA": {
        // Redemption at face value (e.g., T-bill at maturity)
        const redeemAmount = input.amount > post.balance ? post.balance : input.amount;
        const redeemProceeds = (redeemAmount * input.priceUsdc) / (10n ** 18n);
        const proportionalCost = post.balance > 0n
          ? (post.costBasisUsdc * redeemAmount) / post.balance
          : 0n;

        realizedPnL = redeemProceeds - proportionalCost;
        taxImplication = realizedPnL > 0n ? "REALIZED_GAIN" : realizedPnL < 0n ? "REALIZED_LOSS" : "NO_TAX_EVENT";

        post.balance -= redeemAmount;
        post.costBasisUsdc -= proportionalCost;
        break;
      }
    }

    return {
      postPosition: post,
      realizedPnL,
      taxImplication,
      warnings,
    };
  }
}
