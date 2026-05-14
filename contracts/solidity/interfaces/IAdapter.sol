// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Action, TreasuryState} from "../HelixTypes.sol";

/// @title IAdapter
/// @notice Common interface for protocol adapters (ERC20, Aave, Pendle, RobinhoodRWA, Safe).
/// @dev Adapters MUST be callable only by the TreasuryVault. They translate generic Action
///      types into protocol-specific calls. See docs/04-contracts.md §5 and docs/07-integrations.md.
interface IAdapter {
    /// @notice Unique identifier for this adapter (e.g. keccak256("aave-v3-arbitrum")).
    function adapterId() external view returns (bytes32);

    /// @notice The ActionKind values this adapter knows how to execute.
    function supportedActions() external view returns (uint8[] memory);

    /// @notice Executes an action. Must be guarded by `onlyVault`.
    /// @dev Reverts on any post-condition failure. Returns adapter-specific result blob.
    function execute(Action calldata a) external returns (bytes memory result);

    /// @notice Pure simulation: given pre-state, return predicted post-state for one action.
    /// @dev Used by the off-chain agent's Simulator. Must match `execute` semantics.
    function simulate(Action calldata a, TreasuryState calldata pre)
        external
        view
        returns (TreasuryState memory postState);

    /// @notice Per-adapter circuit breaker state.
    function circuitBreakerActive() external view returns (bool);
}
