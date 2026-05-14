// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IProposalRegistry} from "../interfaces/IProposalRegistry.sol";

/// @title HelixSafeModule
/// @notice Registered as a Safe Module. Provides a single privileged entry point for the Safe
///         to approve Helix proposals through their normal multisig flow.
/// @dev See docs/07-integrations.md §1. The module's only privileged action is
///      `ProposalRegistry.approveProposal(...)`; everything else is normal Safe behavior.
contract HelixSafeModule {
    address public immutable safe;
    address public immutable proposalRegistry;

    event ApprovalForwarded(bytes32 indexed proposalId);

    constructor(address _safe, address _proposalRegistry) {
        require(_safe != address(0) && _proposalRegistry != address(0), "Module: zero addr");
        safe = _safe;
        proposalRegistry = _proposalRegistry;
    }

    /// @notice Approve a Helix proposal. Must be called as a Safe transaction (passes Safe's
    ///         threshold check inside the Safe contract before reaching this module).
    function approveProposal(bytes32 proposalId) external {
        require(msg.sender == safe, "Module: not safe");
        IProposalRegistry(proposalRegistry).approveProposal(proposalId);
        emit ApprovalForwarded(proposalId);
    }
}
