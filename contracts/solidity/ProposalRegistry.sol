// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IProposalRegistry} from "./interfaces/IProposalRegistry.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {Action, ProposalState, Verdict, VerdictKind, TreasuryState, MarketState} from "./HelixTypes.sol";

contract ProposalRegistry is IProposalRegistry {
    uint64 public constant PROPOSAL_TTL = 7 days;
    uint64 public override executionTimelock = 1 hours;
    uint256 public constant MIN_AGENT_BOND = 0.01 ether;

    mapping(bytes32 => Proposal) private _proposals;
    bytes32[] private _pendingIds;
    mapping(bytes32 => uint256) private _pendingIdx;

    mapping(address => uint256) public agentBonds;
    mapping(address => bool) private _authorizedAgents;

    address public engine;
    address public policyRegistry;
    address public vault;
    address public safe;
    address public guardian;

    uint256[40] private __gap;

    event ProposalSubmitted(bytes32 indexed proposalId, address indexed agent, uint8 verdictKind);
    event ProposalApproved(bytes32 indexed proposalId, uint256 earliestExecution);
    event ProposalCancelled(bytes32 indexed proposalId, string reason);
    event ProposalExecuted(bytes32 indexed proposalId, bytes32 postStateHash);
    event AgentBondPosted(address indexed agent, uint256 amount);
    event AgentBondSlashed(address indexed agent, uint256 amount, string reason);
    event TimelockUpdated(uint64 newTimelock);

    modifier onlySafe() {
        require(msg.sender == safe, "ProposalRegistry: not safe");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian || msg.sender == safe, "ProposalRegistry: not guardian");
        _;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "ProposalRegistry: not vault");
        _;
    }

    constructor(
        address _engine,
        address _policyRegistry,
        address _safe,
        address _guardian
    ) {
        require(_engine != address(0), "ProposalRegistry: zero engine");
        require(_safe != address(0), "ProposalRegistry: zero safe");
        engine = _engine;
        policyRegistry = _policyRegistry;
        safe = _safe;
        guardian = _guardian;
    }

    function setVault(address _vault) external onlySafe {
        require(vault == address(0), "ProposalRegistry: vault already set");
        require(_vault != address(0), "ProposalRegistry: zero vault");
        vault = _vault;
    }

    function setAuthorizedAgent(address agent, bool authorized) external onlySafe {
        _authorizedAgents[agent] = authorized;
    }

    function isAuthorizedAgent(address agent) external view override returns (bool) {
        return _authorizedAgents[agent];
    }

    function setTimelock(uint64 newTimelock) external onlySafe {
        require(newTimelock >= 1 hours, "ProposalRegistry: timelock too short");
        executionTimelock = newTimelock;
        emit TimelockUpdated(newTimelock);
    }

    function postBond() external payable {
        require(msg.value > 0, "ProposalRegistry: zero bond");
        agentBonds[msg.sender] += msg.value;
        emit AgentBondPosted(msg.sender, msg.value);
    }

    function withdrawBond(uint256 amount) external {
        require(agentBonds[msg.sender] >= amount, "ProposalRegistry: insufficient bond");
        agentBonds[msg.sender] -= amount;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "ProposalRegistry: ETH transfer failed");
    }

    function submitProposal(
        bytes32 policyHash,
        bytes32 marketStateHash,
        Action[] calldata actions,
        bytes32 dryRunResultHash,
        bytes calldata
    ) external override returns (bytes32 proposalId) {
        require(_authorizedAgents[msg.sender], "ProposalRegistry: agent not authorized");
        require(agentBonds[msg.sender] >= MIN_AGENT_BOND, "ProposalRegistry: insufficient bond");
        require(actions.length > 0, "ProposalRegistry: empty actions");
        require(actions.length <= 32, "ProposalRegistry: too many actions");

        proposalId = keccak256(abi.encode(
            msg.sender,
            policyHash,
            marketStateHash,
            actions,
            block.number
        ));
        require(_proposals[proposalId].submittedAt == 0, "ProposalRegistry: duplicate");

        bytes memory stateBytes = abi.encode(
            uint256(0),
            uint256(0), uint256(0), uint256(block.timestamp), bytes32(0)
        );
        bytes memory actionsBytes = _encodeActions(actions);

        bytes memory verdictBytes;
        try IPolicyEngine(engine).evaluate(
            policyHash,
            stateBytes,
            bytes(""),
            actionsBytes
        ) returns (bytes memory vb) {
            verdictBytes = vb;
        } catch {
            _slash(msg.sender, "engine_revert");
            revert("ProposalRegistry: engine revert");
        }

        Verdict memory verdict = _decodeVerdict(verdictBytes);

        ProposalState state = ProposalState.Pending;
        if (verdict.kind == VerdictKind.Reject) {
            bool isHardReject = verdictBytes.length > 0 &&
                _containsHardConstraint(verdict.rejectReason);
            if (isHardReject) {
                _slash(msg.sender, "hard_constraint_violation");
            }
            state = ProposalState.Rejected;
        }

        Action[] storage stored = _proposals[proposalId].actions;
        for (uint256 i = 0; i < actions.length; i++) {
            stored.push(actions[i]);
        }
        _proposals[proposalId].id = proposalId;
        _proposals[proposalId].agent = msg.sender;
        _proposals[proposalId].policyHash = policyHash;
        _proposals[proposalId].marketStateHash = marketStateHash;
        _proposals[proposalId].dryRunResultHash = dryRunResultHash;
        _proposals[proposalId].submittedAt = uint64(block.timestamp);
        _proposals[proposalId].state = state;
        _proposals[proposalId].verdict = verdict;

        if (state == ProposalState.Pending) {
            _pendingIds.push(proposalId);
            _pendingIdx[proposalId] = _pendingIds.length - 1;
        }

        emit ProposalSubmitted(proposalId, msg.sender, uint8(verdict.kind));
    }

    function approveProposal(bytes32 proposalId) external override onlySafe {
        Proposal storage p = _proposals[proposalId];
        require(p.submittedAt > 0, "ProposalRegistry: not found");
        require(p.state == ProposalState.Pending, "ProposalRegistry: not pending");
        require(
            block.timestamp <= p.submittedAt + PROPOSAL_TTL,
            "ProposalRegistry: expired"
        );
        p.state = ProposalState.Approved;
        p.earliestExecution = uint64(block.timestamp + executionTimelock);
        emit ProposalApproved(proposalId, p.earliestExecution);
    }

    function cancelProposal(bytes32 proposalId, string calldata reason)
        external
        override
        onlyGuardian
    {
        Proposal storage p = _proposals[proposalId];
        require(p.submittedAt > 0, "ProposalRegistry: not found");
        require(
            p.state == ProposalState.Pending || p.state == ProposalState.Approved,
            "ProposalRegistry: cannot cancel"
        );
        if (p.state == ProposalState.Approved) {
            require(
                block.timestamp < p.earliestExecution,
                "ProposalRegistry: timelock already expired"
            );
        }
        p.state = ProposalState.Cancelled;
        _removePending(proposalId);
        emit ProposalCancelled(proposalId, reason);
    }

    function executeProposal(bytes32 proposalId) external override {
        Proposal storage p = _proposals[proposalId];
        require(p.state == ProposalState.Approved, "ProposalRegistry: not approved");
        require(
            block.timestamp >= p.earliestExecution,
            "ProposalRegistry: timelock active"
        );
        (bool ok, bytes memory err) = vault.call(
            abi.encodeWithSignature("executeApproved(bytes32)", proposalId)
        );
        if (!ok) {
            if (err.length > 0) {
                assembly { revert(add(err, 32), mload(err)) }
            }
            revert("ProposalRegistry: vault execution failed");
        }
    }

    function markExecuted(bytes32 proposalId, bytes32 postStateHash)
        external
        override
        onlyVault
    {
        Proposal storage p = _proposals[proposalId];
        require(p.state == ProposalState.Approved, "ProposalRegistry: not approved");
        p.state = ProposalState.Executed;
        p.postStateHash = postStateHash;
        _removePending(proposalId);
        emit ProposalExecuted(proposalId, postStateHash);
    }

    function getProposal(bytes32 id)
        external
        view
        override
        returns (Proposal memory)
    {
        return _proposals[id];
    }

    function listPending()
        external
        view
        override
        returns (bytes32[] memory)
    {
        return _pendingIds;
    }

    function _slash(address agent, string memory reason) internal {
        uint256 slash = agentBonds[agent] / 10;
        if (slash == 0) return;
        agentBonds[agent] -= slash;
        if (vault != address(0)) {
            (bool ok,) = payable(vault).call{value: slash}("");
            if (!ok) { /* absorb */ }
        }
        emit AgentBondSlashed(agent, slash, reason);
    }

    function _removePending(bytes32 id) internal {
        uint256 idx = _pendingIdx[id];
        uint256 last = _pendingIds.length - 1;
        if (idx != last) {
            bytes32 lastId = _pendingIds[last];
            _pendingIds[idx] = lastId;
            _pendingIdx[lastId] = idx;
        }
        _pendingIds.pop();
        delete _pendingIdx[id];
    }

    function _encodeActions(Action[] calldata actions)
        internal
        pure
        returns (bytes memory out)
    {
        out = abi.encode(uint256(actions.length));
        for (uint256 i = 0; i < actions.length; i++) {
            Action calldata a = actions[i];
            out = bytes.concat(
                out,
                abi.encode(uint256(uint8(a.kind))),
                abi.encode(a.adapter),
                abi.encode(a.asset),
                abi.encode(a.amount),
                abi.encode(uint256(a.params.length)),
                a.params,
                new bytes((32 - a.params.length % 32) % 32)
            );
        }
    }

    function _decodeVerdict(bytes memory data)
        internal
        pure
        returns (Verdict memory v)
    {
        require(data.length >= 6 * 32, "ProposalRegistry: verdict too short");
        uint256 kind;
        bytes32 ph;
        bytes32 cah;
        bytes32 msh;
        uint64 evaluatedAt;
        assembly {
            kind := mload(add(data, 32))
            ph   := mload(add(data, 64))
            cah  := mload(add(data, 96))
            msh  := mload(add(data, 128))
            evaluatedAt := mload(add(data, 160))
        }
        uint256 reasonLen;
        assembly { reasonLen := mload(add(data, 192)) }
        bytes memory reason = new bytes(reasonLen);
        for (uint256 i = 0; i < reasonLen && 224 + i < data.length; i++) {
            reason[i] = data[224 + i];
        }
        v = Verdict({
            kind: VerdictKind(kind),
            policyHash: ph,
            computedActionsHash: cah,
            marketStateHash: msh,
            evaluatedAt: evaluatedAt,
            rejectReason: reason
        });
    }

    function _containsHardConstraint(bytes memory reason) internal pure returns (bool) {
        bytes memory prefix = bytes("HARD_CONSTRAINT_VIOLATION:");
        if (reason.length < prefix.length) return false;
        for (uint256 i = 0; i < prefix.length; i++) {
            if (reason[i] != prefix[i]) return false;
        }
        return true;
    }
}
