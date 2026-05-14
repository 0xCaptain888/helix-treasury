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
        return _proposeUpdate(newBytecode, new bytes32[](0));
    }

    function proposeUpdate(bytes calldata newBytecode, bytes32[] calldata newConstraintIds) external override onlyOwner returns (bytes32 newHash) {
        return _proposeUpdate(newBytecode, newConstraintIds);
    }

    function activateUpdate(bytes32 newHash) external override onlyOwner {
        _activateUpdate(newHash);
    }

    function activatePending() external override onlyOwner {
        _activateUpdate(pendingPolicyHash);
    }

    function getHardConstraints(bytes32 policyHash) external view override returns (bytes32[] memory) {
        return _policyMeta[policyHash].hardConstraintIds;
    }

    function activePolicyBytecode() external view returns (bytes memory) {
        return _policyBytecode[activePolicyHash];
    }

    // ──────────── Internal ────────────
    function _proposeUpdate(bytes calldata newBytecode, bytes32[] memory newConstraintIds) internal returns (bytes32 newHash) {
        require(newBytecode.length > 0, "PolicyRegistry: empty bytecode");
        newHash = keccak256(newBytecode);
        require(newHash != activePolicyHash, "PolicyRegistry: same policy");
        require(_policyBytecode[newHash].length == 0, "PolicyRegistry: already exists");

        _policyBytecode[newHash] = newBytecode;
        _policyMeta[newHash] = PolicyMeta({
            hash: newHash,
            codeHash: keccak256(newBytecode),
            author: msg.sender,
            activatedAt: 0,
            proposedAt: uint64(block.timestamp),
            active: false,
            hardConstraintIds: newConstraintIds
        });

        pendingPolicyHash = newHash;
        pendingProposedAt = uint64(block.timestamp);

        emit PolicyProposed(newHash, msg.sender, uint64(block.timestamp + POLICY_UPDATE_TIMELOCK));
    }

    function _activateUpdate(bytes32 newHash) internal {
        require(newHash == pendingPolicyHash, "PolicyRegistry: not pending");
        require(block.timestamp >= pendingProposedAt + POLICY_UPDATE_TIMELOCK, "PolicyRegistry: timelock not expired");
        require(_policyBytecode[newHash].length > 0, "PolicyRegistry: bytecode not found");

        // Ensure new constraints are a superset of current
        bytes32[] memory currentConstraints = _policyMeta[activePolicyHash].hardConstraintIds;
        bytes32[] memory newConstraints = _policyMeta[newHash].hardConstraintIds;
        for (uint256 i = 0; i < currentConstraints.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < newConstraints.length; j++) {
                if (currentConstraints[i] == newConstraints[j]) { found = true; break; }
            }
            require(found, "PolicyRegistry: constraints weakened");
        }

        bytes32 previousHash = activePolicyHash;
        _policyMeta[previousHash].active = false;
        _policyMeta[newHash].active = true;
        _policyMeta[newHash].activatedAt = uint64(block.timestamp);
        activePolicyHash = newHash;
        pendingPolicyHash = bytes32(0);
        pendingProposedAt = 0;

        emit PolicyActivated(newHash, previousHash);
    }
}
