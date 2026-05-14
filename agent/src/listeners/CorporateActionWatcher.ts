/**
 * CorporateActionWatcher — monitors Robinhood Chain for corporate action events
 * (dividends, splits, mergers, delistings) and triggers appropriate responses.
 *
 * See docs/07-integrations.md §4.2.
 */

import { EventEmitter } from "node:events";
import { createPublicClient, http, type PublicClient } from "viem";
import type { Logger } from "pino";

export interface CorporateAction {
  type: "dividend" | "split" | "merger" | "delisting";
  asset: `0x${string}`;
  timestamp: number;
  data: Record<string, unknown>;
}

const RWA_ADAPTER_EVENTS = [
  { type: "event", name: "DividendReceived", inputs: [{ type: "address", name: "asset", indexed: true }, { type: "uint256", name: "amount" }] },
  { type: "event", name: "StockSplit", inputs: [{ type: "address", name: "asset", indexed: true }, { type: "uint256", name: "oldBalance" }, { type: "uint256", name: "newBalance" }, { type: "uint256", name: "ratio" }] },
  { type: "event", name: "MergerCompleted", inputs: [{ type: "address", name: "oldAsset", indexed: true }, { type: "address", name: "newAsset", indexed: true }, { type: "uint256", name: "ratio" }] },
  { type: "event", name: "AssetDelisted", inputs: [{ type: "address", name: "asset", indexed: true }] },
] as const;

export class CorporateActionWatcher extends EventEmitter {
  private client: PublicClient;
  private unwatch: (() => void) | null = null;

  constructor(
    private readonly rpcUrl: string,
    private readonly rwaAdapterAddress: `0x${string}`,
    private readonly log: Logger,
  ) {
    super();
    this.client = createPublicClient({
      transport: http(rpcUrl),
    });
  }

  async start(): Promise<void> {
    this.log.info({ adapter: this.rwaAdapterAddress }, "CorporateActionWatcher starting");

    this.unwatch = this.client.watchContractEvent({
      address: this.rwaAdapterAddress,
      abi: RWA_ADAPTER_EVENTS,
      onLogs: (logs) => {
        for (const log of logs) {
          const action = this._parseEvent(log);
          if (action) {
            this.log.info({ type: action.type, asset: action.asset }, "corporate action detected");
            this.emit("corporateAction", action);
          }
        }
      },
    });

    this.log.info("CorporateActionWatcher started");
  }

  stop(): void {
    if (this.unwatch) {
      this.unwatch();
      this.unwatch = null;
    }
  }

  private _parseEvent(log: any): CorporateAction | null {
    const now = Math.floor(Date.now() / 1000);

    switch (log.eventName) {
      case "DividendReceived":
        return {
          type: "dividend",
          asset: log.args.asset,
          timestamp: now,
          data: { amount: log.args.amount?.toString() },
        };
      case "StockSplit":
        return {
          type: "split",
          asset: log.args.asset,
          timestamp: now,
          data: {
            oldBalance: log.args.oldBalance?.toString(),
            newBalance: log.args.newBalance?.toString(),
            ratio: log.args.ratio?.toString(),
          },
        };
      case "MergerCompleted":
        return {
          type: "merger",
          asset: log.args.oldAsset,
          timestamp: now,
          data: {
            newAsset: log.args.newAsset,
            ratio: log.args.ratio?.toString(),
          },
        };
      case "AssetDelisted":
        return {
          type: "delisting",
          asset: log.args.asset,
          timestamp: now,
          data: {},
        };
      default:
        return null;
    }
  }
}
