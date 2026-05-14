// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Action, ProposalState} from "../HelixTypes.sol";

/// @title IProposalRegistry
/// @notice Receives agent proposals, runs PolicyEngine evaluation, manages timelock, surfaces
///         approved proposals to TreasuryVault.execute. See docs/04-contracts.md §3.
interface IProposalRegistry {
    struct Proposal {
        bytes32 id;
        address proposer;
        bytes32 policyHash;
        bytes32 marketStateHash;
        Action[] actions;
        bytes32 dryRunResultHash;
        uint64 submittedAt;
        uint64 expiresAt;
        uint64 earliestExecution;
        ProposalState state;
        bytes32 verdictHash;
    }

    event ProposalSubmitted(bytes32 indexed id, address indexed proposer, bytes32 policyHash);
    event ProposalApproved(bytes32 indexed id, address indexed approver);
    event ProposalRejected(bytes32 indexed id, bytes reason);
    event ProposalCancelled(bytes32 indexed id, string reason);
    event ProposalExecuted(bytes32 indexed id, bytes32 postStateHash);
    event ProposalExpired(bytes32 indexed id);
    event AgentBondSlashed(address indexed agent, uint256 amount, bytes32 indexed proposalId);

    /// @notice Authorized agent submits a candidate proposal. Engine evaluates synchronously.
    function submitProposal(
        bytes32 policyHash,
        bytes32 marketStateHash,
        Action[] calldata actions,
        bytes32 dryRunResultHash,
        bytes calldata agentSig
    ) external returns (bytes32 proposalId);

    /// @notice Safe approves a pending proposal. Starts the execution timelock.
    function approveProposal(bytes32 proposalId) external;

    /// @notice Guardian cancels a proposal during its timelock window.
    function cancelProposal(bytes32 proposalId, string calldata reason) external;

    /// @notice Permissionless execution after timelock elapses. Calls into TreasuryVault.
    function executeProposal(bytes32 proposalId) external;

    /// @notice Marks a proposal as executed; called by TreasuryVault.
    function markExecuted(bytes32 proposalId, bytes32 postStateHash) external;

    function getProposal(bytes32 id) external view returns (Proposal memory);

    function listPending() external view returns (bytes32[] memory);

    function isAuthorizedAgent(address agent) external view returns (bool);

    function executionTimelock() external view returns (uint64);
}
