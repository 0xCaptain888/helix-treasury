// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title ITreasuryVault
interface ITreasuryVault {
    struct AssetEntry {
        address token;
        uint8 tokenType;
        bytes32 adapter;
        bool active;
        uint64 registeredAt;
    }

    event AssetRegistered(address indexed token);
    event AssetDeregistered(address indexed token);
    event Deposited(address indexed from, address indexed token, uint256 amount);
    event Withdrawn(address indexed token, uint256 amount, address indexed to);
    event ProposalExecuted(bytes32 indexed proposalId);
    event EmergencyPaused(address indexed by);
    event EmergencyUnpaused(address indexed by);

    function getState() external view returns (AssetEntry[] memory entries, uint256[] memory balances);
    function getNAV() external view returns (uint256 totalNAVUsdc);
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount, address to) external;
    function executeApproved(bytes32 proposalId) external;
    function emergencyPause() external;
    function emergencyUnpause() external;
    function registerAsset(AssetEntry calldata entry) external;
    function deregisterAsset(address token) external;
    function paused() external view returns (bool);
    function safe() external view returns (address);
    function guardian() external view returns (address);
}
