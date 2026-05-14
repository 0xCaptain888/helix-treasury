// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Action, ProposalState, Verdict} from "../HelixTypes.sol";

/// @title IProposalRegistry
interface IProposalRegistry {

    struct Proposal {
        bytes32 id;
        address agent;
        bytes32 policyHash;
        bytes32 marketStateHash;
        bytes32 dryRunResultHash;
        Action[] actions;
        uint64 submittedAt;
        uint64 earliestExecution;
        ProposalState state;
        Verdict verdict;
        bytes32 postStateHash;
    }

    function PROPOSAL_TTL() external view returns (uint64);
    function executionTimelock() external view returns (uint64);

    function submitProposal(
        bytes32 policyHash,
        bytes32 marketStateHash,
        Action[] calldata actions,
        bytes32 dryRunResultHash,
        bytes calldata agentSig
    ) external returns (bytes32 proposalId);

    function approveProposal(bytes32 proposalId) external;
    function cancelProposal(bytes32 proposalId, string calldata reason) external;
    function executeProposal(bytes32 proposalId) external;
    function markExecuted(bytes32 proposalId, bytes32 postStateHash) external;

    function getProposal(bytes32 id) external view returns (Proposal memory);
    function listPending() external view returns (bytes32[] memory);
    function isAuthorizedAgent(address agent) external view returns (bool);
}
