// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ITreasuryVault
/// @notice Custodies treasury funds; dispatches actions to adapters only after proposal
///         clears PolicyEngine + Safe + timelock + execution-time re-evaluation. NON-upgradable.
///         See docs/04-contracts.md §4.
interface ITreasuryVault {
    enum Protocol {
        WALLET,
        AAVE,
        PENDLE,
        RWA,
        UNISWAP
    }

    struct AssetEntry {
        address token;
        uint8 decimals;
        bool isStable;
        bool isLiquid;
        Protocol protocol;
        address adapter; // address(0) for direct WALLET holdings
        bool active;
    }

    event AssetRegistered(address indexed token, bytes32 adapter);
    event AssetDeregistered(address indexed token);
    event Executed(bytes32 indexed proposalId);
    event ActionDispatched(uint8 indexed actionType, address indexed adapter, bytes data);
    event EmergencyPaused(address by);
    event EmergencyUnpaused(address by);
    event Deposited(address indexed from, address indexed token, uint256 amount);

    function getState() external view returns (AssetEntry[] memory entries, uint256[] memory balances);
    function getNAV() external view returns (uint256 totalNAVUsdc);

    /// @notice Permissionless deposit; anyone can fund a treasury.
    function deposit(address token, uint256 amount) external;

    /// @notice Safe-controlled withdrawal with timelock (for emergency reorg out of Helix).
    function withdraw(address token, uint256 amount, address to) external;

    /// @notice Permissionless execution of a proposal that has passed all gates.
    /// @dev Re-runs PolicyEngine.evaluate at entry; reverts on stale state.
    function executeApproved(bytes32 proposalId) external;

    function emergencyPause() external; // guardian
    function emergencyUnpause() external; // safe

    function registerAsset(AssetEntry calldata entry) external; // safe
    function deregisterAsset(address token) external; // safe + timelock

    function paused() external view returns (bool);
    function safe() external view returns (address);
    function guardian() external view returns (address);
}
