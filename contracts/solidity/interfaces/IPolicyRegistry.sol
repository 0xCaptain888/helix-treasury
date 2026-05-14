// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IPolicyRegistry
/// @notice Stores policy bytecode and metadata, one registry per treasury.
/// @dev Policy updates require Safe approval + 7-day timelock. Hard constraints can only be
///      tightened, never relaxed. See docs/02-policy-engine.md §10 and docs/04-contracts.md §2.
interface IPolicyRegistry {
    struct PolicyMeta {
        bytes32 hash;
        bytes32 codeHash;
        address author;
        uint64 activatedAt;
        uint64 proposedAt;
        bool active;
        bytes32[] hardConstraintIds;
    }

    event PolicyProposed(bytes32 indexed hash, address indexed by, uint64 earliestActivation);
    event PolicyActivated(bytes32 indexed hash, bytes32 indexed previousHash);
    event PolicyRejected(bytes32 indexed hash, bytes reason);

    /// @notice The hash of the currently-active policy.
    function activePolicyHash() external view returns (bytes32);

    /// @notice Returns the active policy hash and its metadata.
    function activePolicy() external view returns (bytes32 hash, PolicyMeta memory);

    /// @notice Returns the bytecode and metadata for any historical or pending policy.
    function getPolicy(bytes32 hash) external view returns (bytes memory bytecode, PolicyMeta memory meta);

    /// @notice Submit a policy update for the 7-day public review window.
    /// @dev Caller must be the treasury owner Safe. The new bytecode is run through the verifier
    ///      at proposal time and again at activation time.
    function proposeUpdate(bytes calldata newBytecode) external returns (bytes32 newHash);

    /// @notice Activate a previously proposed update after the timelock has elapsed.
    /// @dev Re-runs the verifier and confirms hardConstraints ⊇ current.
    function activateUpdate(bytes32 newHash) external;

    /// @notice Returns the hard constraints attached to a given policy.
    function getHardConstraints(bytes32 policyHash) external view returns (bytes32[] memory);
}
