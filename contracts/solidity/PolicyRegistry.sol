// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPolicyRegistry} from "./interfaces/IPolicyRegistry.sol";

/// @title PolicyRegistry
/// @notice Stores policy bytecode + metadata for one treasury. Updates gated by Safe + 7-day timelock.
/// @dev See docs/02-policy-engine.md §10 and docs/04-contracts.md §2.
contract PolicyRegistry is IPolicyRegistry {
    // ──────────── Constants ────────────
    uint256 public constant POLICY_UPDATE_TIMELOCK = 7 days;

    // ──────────── Storage ────────────
    mapping(bytes32 => bytes) private _policyBytecode;
    mapping(bytes32 => PolicyMeta) private _policyMeta;

    bytes32 public override activePolicyHash;
    bytes32 public pendingPolicyHash;
    uint64 public pendingProposedAt;

    address public owner; // Safe
    address public verifier; // PolicyVerifier
    address public hardConstraintsLib;

    // Reserved storage slots for future-proofing
    uint256[40] private __gap;

    // ──────────── Modifiers ────────────
    modifier onlyOwner() {
        require(msg.sender == owner, "PolicyRegistry: not owner");
        _;
    }

    // ──────────── Constructor ────────────
    constructor(
        address _owner,
        address _verifier,
        address _hardConstraintsLib,
        bytes memory initialBytecode,
        bytes32[] memory initialHardConstraintIds
    ) {
        require(_owner != address(0) && _verifier != address(0), "PolicyRegistry: zero addr");
        owner = _owner;
        verifier = _verifier;
        hardConstraintsLib = _hardConstraintsLib;

        // Activate initial policy without timelock (treasury bootstrap).
        bytes32 hash = keccak256(initialBytecode);
        _policyBytecode[hash] = initialBytecode;
        _policyMeta[hash] = PolicyMeta({
            hash: hash,
            codeHash: keccak256(initialBytecode),
            author: _owner,
            activatedAt: uint64(block.timestamp),
            proposedAt: uint64(block.timestamp),
            active: true,
            hardConstraintIds: initialHardConstraintIds
        });
        activePolicyHash = hash;
        emit PolicyActivated(hash, bytes32(0));
    }

    // ──────────── External ────────────
    function activePolicy() external view override returns (bytes32 hash, PolicyMeta memory) {
        hash = activePolicyHash;
        return (hash, _policyMeta[hash]);
    }

    function getPolicy(bytes32 hash) external view override returns (bytes memory bytecode, PolicyMeta memory meta) {
        bytecode = _policyBytecode[hash];
        meta = _policyMeta[hash];
    }

    function proposeUpdate(bytes calldata newBytecode) external override onlyOwner returns (bytes32 newHash) {
        // TODO(mulerun): call verifier.verify(newBytecode, activePolicyHash)
        // TODO(mulerun): emit PolicyProposed
        // TODO(mulerun): store bytecode, set pendingPolicyHash, set pendingProposedAt
        revert("PolicyRegistry: not implemented");
    }

    function activateUpdate(bytes32 newHash) external override onlyOwner {
        // TODO(mulerun):
        // require(newHash == pendingPolicyHash, ...)
        // require(block.timestamp >= pendingProposedAt + POLICY_UPDATE_TIMELOCK, ...)
        // re-run verifier
        // ensure new hardConstraintIds ⊇ current
        // flip active flag, emit PolicyActivated
        revert("PolicyRegistry: not implemented");
    }

    function getHardConstraints(bytes32 policyHash) external view override returns (bytes32[] memory) {
        return _policyMeta[policyHash].hardConstraintIds;
    }
}
