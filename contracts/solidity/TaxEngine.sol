// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ITaxEngine} from "./interfaces/ITaxEngine.sol";
import {Action, ActionKind, TaxEventKind} from "./HelixTypes.sol";

/// @title TaxEngine
/// @notice Records tax events at execution time using configurable lot method (FIFO/LIFO/HIFO).
/// @dev See docs/04-contracts.md §6.
contract TaxEngine is ITaxEngine {
    struct Lot {
        uint256 amount;
        uint256 costBasisUsd6; // total cost in USDC-6
        uint64 acquiredAt;
    }

    TaxEvent[] private _events;
    mapping(bytes32 => uint256[]) private _eventsByProposal;
    mapping(address => Lot[]) private _lotsByAsset;

    bytes8 public override jurisdiction;
    uint8 public override lotMethod; // 0=FIFO, 1=LIFO, 2=HIFO
    address public safe;
    address public vault;

    uint256[40] private __gap;

    modifier onlySafe() {
        require(msg.sender == safe, "TaxEngine: not safe");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "TaxEngine: not vault");
        _;
    }

    constructor(address _safe, address _vault, bytes8 _jurisdiction, uint8 _lotMethod) {
        require(_lotMethod <= 2, "TaxEngine: bad lot method");
        safe = _safe;
        vault = _vault;
        jurisdiction = _jurisdiction;
        lotMethod = _lotMethod;
    }

    function recordExecution(bytes32 proposalId, Action[] calldata actions) external override onlyVault {
        for (uint256 i = 0; i < actions.length; i++) {
            Action calldata a = actions[i];
            ActionKind k = a.kind;

            if (k == ActionKind.SUPPLY || k == ActionKind.BUY_RWA || k == ActionKind.BUY_PT) {
                // Acquisition: add a new lot
                _lotsByAsset[a.asset].push(Lot({
                    amount: a.amount,
                    costBasisUsd6: a.amount, // 1:1 placeholder; real price comes via params
                    acquiredAt: uint64(block.timestamp)
                }));

                bytes32 evId = keccak256(abi.encodePacked(proposalId, a.asset, i));
                uint256 idx = _events.length;
                _events.push(TaxEvent({
                    id: evId,
                    proposalId: proposalId,
                    occurredAt: uint64(block.timestamp),
                    kind: TaxEventKind.INTERNAL_TRANSFER, // acquisition — no PnL
                    asset: a.asset,
                    amount: a.amount,
                    costBasis: a.amount,
                    proceedsUsd6: 0,
                    realizedPnlUsd6: 0,
                    lotMethod: lotMethod,
                    jurisdiction: jurisdiction,
                    metadata: bytes32(0)
                }));
                _eventsByProposal[proposalId].push(idx);
                emit TaxEventRecorded(evId, proposalId, TaxEventKind.INTERNAL_TRANSFER, a.asset, a.amount, 0);

            } else if (
                k == ActionKind.WITHDRAW || k == ActionKind.SELL_RWA ||
                k == ActionKind.SELL_PT
            ) {
                // Disposition: select lot, compute PnL
                (uint256 costBasis, uint256 consumed) = _consumeLots(a.asset, a.amount);
                int256 pnl = int256(a.amount) - int256(costBasis);
                TaxEventKind evKind = pnl >= 0 ? TaxEventKind.REALIZED_GAIN : TaxEventKind.REALIZED_LOSS;

                bytes32 evId = keccak256(abi.encodePacked(proposalId, a.asset, i));
                uint256 idx = _events.length;
                _events.push(TaxEvent({
                    id: evId,
                    proposalId: proposalId,
                    occurredAt: uint64(block.timestamp),
                    kind: evKind,
                    asset: a.asset,
                    amount: consumed,
                    costBasis: costBasis,
                    proceedsUsd6: a.amount,
                    realizedPnlUsd6: pnl,
                    lotMethod: lotMethod,
                    jurisdiction: jurisdiction,
                    metadata: bytes32(0)
                }));
                _eventsByProposal[proposalId].push(idx);
                emit TaxEventRecorded(evId, proposalId, evKind, a.asset, consumed, pnl);

            } else if (k == ActionKind.SWAP) {
                // SWAP: sell side — consume lots for the sold asset
                (uint256 costBasis, uint256 consumed) = _consumeLots(a.asset, a.amount);
                int256 pnl = int256(a.amount) - int256(costBasis);
                TaxEventKind evKind = pnl >= 0 ? TaxEventKind.REALIZED_GAIN : TaxEventKind.REALIZED_LOSS;

                bytes32 evId = keccak256(abi.encodePacked(proposalId, a.asset, i));
                uint256 idx = _events.length;
                _events.push(TaxEvent({
                    id: evId,
                    proposalId: proposalId,
                    occurredAt: uint64(block.timestamp),
                    kind: evKind,
                    asset: a.asset,
                    amount: consumed,
                    costBasis: costBasis,
                    proceedsUsd6: a.amount,
                    realizedPnlUsd6: pnl,
                    lotMethod: lotMethod,
                    jurisdiction: jurisdiction,
                    metadata: bytes32(0)
                }));
                _eventsByProposal[proposalId].push(idx);
                emit TaxEventRecorded(evId, proposalId, evKind, a.asset, consumed, pnl);

                // SWAP: buy side — create a lot for the acquired asset
                // The target asset and amount are encoded in params
                if (a.params.length >= 52) {
                    (address buyAsset, uint256 buyAmount) = abi.decode(a.params, (address, uint256));
                    if (buyAsset != address(0) && buyAmount > 0) {
                        _lotsByAsset[buyAsset].push(Lot({
                            amount: buyAmount,
                            costBasisUsd6: a.amount, // cost basis = what was sold
                            acquiredAt: uint64(block.timestamp)
                        }));
                    }
                }

            } else if (k == ActionKind.TRANSFER) {
                bytes32 evId = keccak256(abi.encodePacked(proposalId, a.asset, i));
                uint256 idx = _events.length;
                _events.push(TaxEvent({
                    id: evId,
                    proposalId: proposalId,
                    occurredAt: uint64(block.timestamp),
                    kind: TaxEventKind.INTERNAL_TRANSFER,
                    asset: a.asset,
                    amount: a.amount,
                    costBasis: 0,
                    proceedsUsd6: 0,
                    realizedPnlUsd6: 0,
                    lotMethod: lotMethod,
                    jurisdiction: jurisdiction,
                    metadata: bytes32(0)
                }));
                _eventsByProposal[proposalId].push(idx);
                emit TaxEventRecorded(evId, proposalId, TaxEventKind.INTERNAL_TRANSFER, a.asset, a.amount, 0);
            }
            // NOOP, SET_FLAG, BORROW, REPAY, etc.: skip
        }
    }

    /// @dev Consume lots for a disposition using the configured lotMethod. Returns (totalCostBasis, totalConsumed).
    function _consumeLots(address asset, uint256 amount) internal returns (uint256 totalCost, uint256 totalConsumed) {
        Lot[] storage lots = _lotsByAsset[asset];
        uint256 remaining = amount;

        while (remaining > 0 && lots.length > 0) {
            uint256 idx = _pickLotIndex(lots);
            Lot storage lot = lots[idx];

            uint256 take = remaining > lot.amount ? lot.amount : remaining;
            uint256 cost = (lot.costBasisUsd6 * take) / lot.amount;

            totalCost += cost;
            totalConsumed += take;
            remaining -= take;

            if (take == lot.amount) {
                // Remove lot using shift-left to preserve ordering (required for FIFO correctness)
                for (uint256 j = idx; j < lots.length - 1; j++) {
                    lots[j] = lots[j + 1];
                }
                lots.pop();
            } else {
                lot.costBasisUsd6 -= cost;
                lot.amount -= take;
            }
        }
    }

    /// @dev Pick the lot index based on lotMethod (0=FIFO, 1=LIFO, 2=HIFO).
    function _pickLotIndex(Lot[] storage lots) internal view returns (uint256) {
        if (lotMethod == 1) {
            // LIFO: last element
            return lots.length - 1;
        } else if (lotMethod == 2) {
            // HIFO: highest cost-basis-per-unit
            uint256 best = 0;
            uint256 bestRatio = 0;
            for (uint256 j = 0; j < lots.length; j++) {
                uint256 ratio = (lots[j].costBasisUsd6 * 1e18) / lots[j].amount;
                if (ratio > bestRatio) {
                    bestRatio = ratio;
                    best = j;
                }
            }
            return best;
        }
        // FIFO (0): first element
        return 0;
    }

    function recordCorporateAction(address asset, TaxEventKind kind, uint256 amount, bytes32 metadata)
        external
        override
        onlyVault
    {
        bytes32 evId = keccak256(abi.encodePacked(asset, kind, amount, block.timestamp));
        uint256 idx = _events.length;
        bytes32 proposalId = bytes32(0);
        _events.push(TaxEvent({
            id: evId,
            proposalId: proposalId,
            occurredAt: uint64(block.timestamp),
            kind: kind,
            asset: asset,
            amount: amount,
            costBasis: 0,
            proceedsUsd6: 0,
            realizedPnlUsd6: 0,
            lotMethod: lotMethod,
            jurisdiction: jurisdiction,
            metadata: metadata
        }));
        _eventsByProposal[proposalId].push(idx);
        emit TaxEventRecorded(evId, proposalId, kind, asset, amount, 0);
    }

    function exportPeriod(uint64 startTs, uint64 endTs) external view override returns (TaxEvent[] memory) {
        // First pass: count matching events
        uint256 count = 0;
        for (uint256 i = 0; i < _events.length; i++) {
            if (_events[i].occurredAt >= startTs && _events[i].occurredAt <= endTs) {
                count++;
            }
        }
        // Second pass: collect them
        TaxEvent[] memory result = new TaxEvent[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < _events.length; i++) {
            if (_events[i].occurredAt >= startTs && _events[i].occurredAt <= endTs) {
                result[j++] = _events[i];
            }
        }
        return result;
    }

    function setJurisdiction(bytes8 code) external override onlySafe {
        emit JurisdictionChanged(jurisdiction, code);
        jurisdiction = code;
    }

    function setLotMethod(uint8 method) external override onlySafe {
        require(method <= 2, "TaxEngine: bad method");
        emit LotMethodChanged(lotMethod, method);
        lotMethod = method;
    }
}
