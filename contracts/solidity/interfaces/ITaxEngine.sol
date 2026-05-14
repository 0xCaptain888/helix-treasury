// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Action, TaxEventKind} from "../HelixTypes.sol";

/// @title ITaxEngine
/// @notice Records tax events at execution time; produces jurisdiction-aware reports.
/// @dev Hooked from TreasuryVault.executeApproved. See docs/04-contracts.md §6.
interface ITaxEngine {
    struct TaxEvent {
        bytes32 id;
        bytes32 proposalId;
        uint64 occurredAt;
        TaxEventKind kind;
        address asset;
        uint256 amount;
        uint256 costBasis;
        bytes8 jurisdiction; // ISO-3166-1 alpha-2
        bytes32 metadata; // hash of extended off-chain metadata
    }

    event TaxEventRecorded(
        bytes32 indexed id,
        bytes32 indexed proposalId,
        TaxEventKind kind,
        address indexed asset,
        uint256 amount,
        int256 realizedPnL
    );
    event JurisdictionChanged(bytes8 from, bytes8 to);
    event LotMethodChanged(uint8 from, uint8 to);

    /// @notice Records all tax events arising from one executed proposal.
    function recordExecution(bytes32 proposalId, Action[] calldata actions) external;

    /// @notice Special path for corporate-action events (dividends, splits, mergers).
    function recordCorporateAction(address asset, TaxEventKind kind, uint256 amount, bytes32 metadata) external;

    function exportPeriod(uint64 startTs, uint64 endTs) external view returns (TaxEvent[] memory);

    function setJurisdiction(bytes8 code) external;
    function setLotMethod(uint8 method) external; // FIFO=0, LIFO=1, HIFO=2

    function jurisdiction() external view returns (bytes8);
    function lotMethod() external view returns (uint8);
}
