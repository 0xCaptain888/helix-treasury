// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IProposalRegistry} from "../interfaces/IProposalRegistry.sol";

/// @title SafeProposalAdapter
/// @notice Formats Helix proposals as Safe-compatible transactions for the Safe Transaction Service.
///         Used by the off-chain agent to present proposals in the Safe UI with full context
///         (policy hash, dry-run results, predicted post-state).
/// @dev See docs/07-integrations.md §1.3.
contract SafeProposalAdapter {
    address public immutable safe;
    address public immutable proposalRegistry;

    struct SafeTxContext {
        bytes32 proposalId;
        bytes32 policyHash;
        bytes32 dryRunHash;
        string rationale;
    }

    mapping(bytes32 => SafeTxContext) public contexts;

    event ContextAttached(bytes32 indexed proposalId, bytes32 indexed safeTxHash);

    constructor(address _safe, address _proposalRegistry) {
        require(_safe != address(0) && _proposalRegistry != address(0), "SafeProposalAdapter: zero addr");
        safe = _safe;
        proposalRegistry = _proposalRegistry;
    }

    /// @notice Attach context metadata to a Safe transaction for UI display.
    /// @param safeTxHash The Safe transaction hash (from Safe Transaction Service).
    /// @param ctx The Helix proposal context to display alongside the Safe tx.
    function attachContext(bytes32 safeTxHash, SafeTxContext calldata ctx) external {
        require(msg.sender == safe, "SafeProposalAdapter: not safe");
        contexts[safeTxHash] = ctx;
        emit ContextAttached(ctx.proposalId, safeTxHash);
    }

    /// @notice Retrieve context for a Safe transaction.
    function getContext(bytes32 safeTxHash) external view returns (SafeTxContext memory) {
        return contexts[safeTxHash];
    }

    /// @notice Build the call data for ProposalRegistry.approveProposal, formatted for Safe.
    function buildApprovalCalldata(bytes32 proposalId) external pure returns (bytes memory) {
        return abi.encodeWithSelector(
            IProposalRegistry.approveProposal.selector,
            proposalId
        );
    }
}
