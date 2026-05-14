// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ITaxEngine} from "./interfaces/ITaxEngine.sol";
import {Action, TaxEventKind} from "./HelixTypes.sol";

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
        safe = _safe;
        vault = _vault;
        jurisdiction = _jurisdiction;
        lotMethod = _lotMethod;
    }

    function recordExecution(bytes32 proposalId, Action[] calldata actions) external override onlyVault {
        // TODO(mulerun): iterate over actions, determine kind (acquisition vs disposition),
        // update lots, compute realized PnL using lotMethod, emit TaxEventRecorded.
        revert("TaxEngine: not implemented");
    }

    function recordCorporateAction(address asset, TaxEventKind kind, uint256 amount, bytes32 metadata)
        external
        override
        onlyVault
    {
        // TODO(mulerun): handle dividend/split/merger/delisting events
        revert("TaxEngine: not implemented");
    }

    function exportPeriod(uint64 startTs, uint64 endTs) external view override returns (TaxEvent[] memory) {
        // TODO(mulerun): filter _events by occurredAt
        revert("TaxEngine: not implemented");
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
