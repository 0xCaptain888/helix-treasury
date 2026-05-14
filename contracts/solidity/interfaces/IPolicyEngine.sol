// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IPolicyEngine
/// @notice Interface for the Stylus PolicyEngine.
interface IPolicyEngine {
    /// @notice Evaluate proposed actions against policy. Returns ABI-encoded Verdict.
    function evaluate(
        bytes32 policyHash,
        bytes calldata stateBytes,
        bytes calldata marketBytes,
        bytes calldata proposedBytes
    ) external returns (bytes memory verdictBytes);

    /// @notice Check only hard constraints. Cheaper than full evaluate().
    function check_hard_constraints(
        bytes32 policyHash,
        bytes calldata stateBytes,
        bytes calldata actionsBytes
    ) external returns (bytes memory result);

    /// @notice Get the PolicyRegistry address this engine reads from.
    function get_registry() external view returns (address);
}
