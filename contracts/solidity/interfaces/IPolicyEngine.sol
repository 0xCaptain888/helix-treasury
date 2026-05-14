// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Action, TreasuryState, MarketState, Verdict, VerdictKind} from "../HelixTypes.sol";

/// @title IPolicyEngine
/// @notice Solidity interface to the Stylus-implemented PolicyEngine.
/// @dev The engine is stateless; all inputs are passed explicitly. See docs/02-policy-engine.md.
interface IPolicyEngine {
    /// @notice Evaluates a proposal against a stored policy and current treasury+market state.
    /// @param policyHash    The hash of the active policy (must be present in PolicyRegistry).
    /// @param state         Current treasury snapshot.
    /// @param market        Current market snapshot from OracleAggregator.
    /// @param proposed      The list of actions the agent is proposing.
    /// @return v            Deterministic verdict with reject reason if applicable.
    function evaluate(
        bytes32 policyHash,
        TreasuryState calldata state,
        MarketState calldata market,
        Action[] calldata proposed
    ) external view returns (Verdict memory v);

    /// @notice Checks whether all hard constraints of a policy hold for a hypothetical post-state.
    /// @dev Called both at submission time (against simulated post-state) and at execution time
    ///      (against live post-state) as defense-in-depth.
    function checkHardConstraints(
        bytes32 policyHash,
        TreasuryState calldata postState
    ) external view returns (bool ok, bytes memory failedConstraint);

    /// @notice Pure computation of the canonical action list for the given inputs.
    /// @dev Used by the off-chain agent during simulation and by the on-chain engine for verdict.
    function computeActions(
        bytes32 policyHash,
        TreasuryState calldata state,
        MarketState calldata market
    ) external view returns (Action[] memory);

    /// @notice Bytecode address of the verifier that vets policies before activation.
    function verifier() external view returns (address);
}
