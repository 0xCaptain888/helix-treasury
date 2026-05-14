// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IProposalRegistry} from "./interfaces/IProposalRegistry.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
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
        // TODO(mulerun): block withdrawal during cooldown; verify no slashable proposals pending
        revert("ProposalRegistry: not implemented");
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

        // TODO(mulerun):
        //   1. compute proposalId = keccak256(abi.encode(...))
        //   2. verify agentSig
        //   3. call IPolicyEngine(engine).evaluate(policyHash, currentState, currentMarket, actions)
        //   4. if Verdict.Reject and reason == MALFORMED → slash bond
        //   5. if Verdict.Approve → store proposal, push to _pendingIds
        //   6. emit ProposalSubmitted

        revert("ProposalRegistry: not implemented");
    }

    function approveProposal(bytes32 proposalId) external override onlySafe {
        // TODO(mulerun):
        //   require state == Pending
        //   set state = Approved, earliestExecution = now + executionTimelock
        //   emit ProposalApproved
        revert("ProposalRegistry: not implemented");
    }

    function cancelProposal(bytes32 proposalId, string calldata reason) external override onlyGuardian {
        // TODO(mulerun):
        //   require state in {Pending, Approved} and not yet executed
        //   require block.timestamp < earliestExecution (i.e. still in timelock if approved)
        //   set state = Cancelled
        //   emit ProposalCancelled
        revert("ProposalRegistry: not implemented");
    }

    function executeProposal(bytes32 proposalId) external override {
        // Permissionless. Forwards to TreasuryVault which does the heavy lifting.
        // TODO(mulerun): ITreasuryVault(vault).executeApproved(proposalId);
        revert("ProposalRegistry: not implemented");
    }

    function markExecuted(bytes32 proposalId, bytes32 postStateHash) external override onlyVault {
        // TODO(mulerun): update state to Executed; remove from pending; emit ProposalExecuted
        revert("ProposalRegistry: not implemented");
    }

    function getProposal(bytes32 id) external view override returns (Proposal memory) {
        return _proposals[id];
    }

    function listPending() external view override returns (bytes32[] memory) {
        return _pendingIds;
    }
}
