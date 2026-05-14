// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IProposalRegistry} from "./interfaces/IProposalRegistry.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {ITreasuryVault} from "./interfaces/ITreasuryVault.sol";
import {Action, ProposalState, Verdict, VerdictKind, TreasuryState, MarketState} from "./HelixTypes.sol";

/// @title ProposalRegistry
/// @notice Receives agent proposals, calls PolicyEngine for verdicts, manages timelock,
///         surfaces approved proposals to TreasuryVault.executeApproved.
/// @dev See docs/04-contracts.md §3.
contract ProposalRegistry is IProposalRegistry {
    // ──────────── Constants ────────────
    uint64 public constant PROPOSAL_TTL = 7 days;
    uint256 public constant MIN_AGENT_BOND = 0.01 ether;

    // ──────────── Storage ────────────
    mapping(bytes32 => Proposal) private _proposals;
    bytes32[] private _pendingIds;
    mapping(bytes32 => uint256) private _pendingIdx;

    uint64 public override executionTimelock = 24 hours;
    mapping(address => uint256) public agentBonds;
    mapping(address => bool) private _authorizedAgents;

    address public engine; // PolicyEngine (Stylus)
    address public policyRegistry;
    address public vault; // TreasuryVault
    address public guardian; // Safe
    address public safe; // owner Safe

    uint256[40] private __gap;

    // ──────────── Modifiers ────────────
    modifier onlySafe() {
        require(msg.sender == safe, "ProposalRegistry: not safe");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "ProposalRegistry: not guardian");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "ProposalRegistry: not vault");
        _;
    }

    // ──────────── Constructor ────────────
    constructor(address _engine, address _policyRegistry, address _safe, address _guardian) {
        require(_engine != address(0) && _safe != address(0), "ProposalRegistry: zero addr");
        engine = _engine;
        policyRegistry = _policyRegistry;
        safe = _safe;
        guardian = _guardian;
    }

    function setVault(address _vault) external onlySafe {
        require(vault == address(0), "ProposalRegistry: vault already set");
        vault = _vault;
    }

    function setAuthorizedAgent(address agent, bool authorized) external onlySafe {
        _authorizedAgents[agent] = authorized;
    }

    function isAuthorizedAgent(address agent) external view override returns (bool) {
        return _authorizedAgents[agent];
    }

    // ──────────── Agent bond ────────────
    function postBond() external payable {
        require(msg.value > 0, "ProposalRegistry: zero bond");
        agentBonds[msg.sender] += msg.value;
    }

    function withdrawBond(uint256 amount) external {
        require(amount > 0, "ProposalRegistry: zero amount");
        require(agentBonds[msg.sender] >= amount, "ProposalRegistry: insufficient bond");
        agentBonds[msg.sender] -= amount;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "ProposalRegistry: transfer failed");
    }

    // ──────────── Proposal submission ────────────
    function submitProposal(
        bytes32 policyHash,
        bytes32 marketStateHash,
        Action[] calldata actions,
        bytes32 dryRunResultHash,
        bytes calldata agentSig
    ) external override returns (bytes32 proposalId) {
        require(_authorizedAgents[msg.sender], "ProposalRegistry: agent not authorized");
        require(agentBonds[msg.sender] >= MIN_AGENT_BOND, "ProposalRegistry: insufficient bond");

        // 1. Compute proposalId
        proposalId = keccak256(
            abi.encode(msg.sender, policyHash, marketStateHash, block.timestamp, keccak256(abi.encode(actions)))
        );

        // 2. Call PolicyEngine for verdict
        TreasuryState memory emptyState;
        MarketState memory emptyMarket;
        Verdict memory v = IPolicyEngine(engine).evaluate(policyHash, emptyState, emptyMarket, actions);
        bytes32 verdictHash = keccak256(abi.encode(v));

        // 3. Handle rejection
        if (v.kind == VerdictKind.Reject) {
            // Check if reason contains "MALFORMED" — slash 50% of bond
            if (_containsMalformed(v.rejectReason)) {
                uint256 slashAmount = agentBonds[msg.sender] / 2;
                agentBonds[msg.sender] -= slashAmount;
                emit AgentBondSlashed(msg.sender, slashAmount, proposalId);
            }
            emit ProposalRejected(proposalId, v.rejectReason);
            return proposalId;
        }

        require(v.kind == VerdictKind.Approve, "ProposalRegistry: stale verdict");

        // 4. Store proposal with state = Pending
        Proposal storage p = _proposals[proposalId];
        p.id = proposalId;
        p.proposer = msg.sender;
        p.policyHash = policyHash;
        p.marketStateHash = marketStateHash;
        p.dryRunResultHash = dryRunResultHash;
        p.submittedAt = uint64(block.timestamp);
        p.expiresAt = uint64(block.timestamp) + PROPOSAL_TTL;
        p.state = ProposalState.Pending;
        p.verdictHash = verdictHash;

        // Copy actions into storage
        for (uint256 i = 0; i < actions.length; i++) {
            p.actions.push(actions[i]);
        }

        // 5. Push to pending list
        _pendingIdx[proposalId] = _pendingIds.length;
        _pendingIds.push(proposalId);

        // 6. Emit event
        emit ProposalSubmitted(proposalId, msg.sender, policyHash);
    }

    /// @dev Checks whether rejectReason bytes contain the string "MALFORMED".
    function _containsMalformed(bytes memory reason) internal pure returns (bool) {
        bytes memory target = bytes("MALFORMED");
        if (reason.length < target.length) return false;
        for (uint256 i = 0; i <= reason.length - target.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < target.length; j++) {
                if (reason[i + j] != target[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function approveProposal(bytes32 proposalId) external override onlySafe {
        Proposal storage p = _proposals[proposalId];
        require(p.state == ProposalState.Pending, "ProposalRegistry: not pending");
        p.state = ProposalState.Approved;
        p.earliestExecution = uint64(block.timestamp) + executionTimelock;
        emit ProposalApproved(proposalId, msg.sender);
    }

    function cancelProposal(bytes32 proposalId, string calldata reason) external override onlyGuardian {
        Proposal storage p = _proposals[proposalId];
        require(
            p.state == ProposalState.Pending || p.state == ProposalState.Approved,
            "ProposalRegistry: not cancellable"
        );
        p.state = ProposalState.Cancelled;
        _removePending(proposalId);
        emit ProposalCancelled(proposalId, reason);
    }

    function executeProposal(bytes32 proposalId) external override {
        Proposal storage p = _proposals[proposalId];
        require(p.state == ProposalState.Approved, "ProposalRegistry: not approved");
        require(block.timestamp >= p.earliestExecution, "ProposalRegistry: timelock active");
        require(block.timestamp <= p.expiresAt, "ProposalRegistry: proposal expired");
        ITreasuryVault(vault).executeApproved(proposalId);
    }

    function markExecuted(bytes32 proposalId, bytes32 postStateHash) external override onlyVault {
        Proposal storage p = _proposals[proposalId];
        require(p.state == ProposalState.Approved, "ProposalRegistry: not approved");
        p.state = ProposalState.Executed;
        _removePending(proposalId);
        emit ProposalExecuted(proposalId, postStateHash);
    }

    // ──────────── Internal helpers ────────────
    /// @dev Swap-and-pop removal from _pendingIds.
    function _removePending(bytes32 proposalId) internal {
        uint256 idx = _pendingIdx[proposalId];
        uint256 lastIdx = _pendingIds.length - 1;
        if (idx != lastIdx) {
            bytes32 lastId = _pendingIds[lastIdx];
            _pendingIds[idx] = lastId;
            _pendingIdx[lastId] = idx;
        }
        _pendingIds.pop();
        delete _pendingIdx[proposalId];
    }

    function getProposal(bytes32 id) external view override returns (Proposal memory) {
        return _proposals[id];
    }

    function listPending() external view override returns (bytes32[] memory) {
        return _pendingIds;
    }
}
