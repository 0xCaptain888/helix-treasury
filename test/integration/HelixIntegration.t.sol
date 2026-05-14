// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {TreasuryFactory} from "../../contracts/solidity/TreasuryFactory.sol";
import {TreasuryVault} from "../../contracts/solidity/TreasuryVault.sol";
import {PolicyRegistry} from "../../contracts/solidity/PolicyRegistry.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";
import {TaxEngine} from "../../contracts/solidity/TaxEngine.sol";
import {OracleAggregator} from "../../contracts/solidity/OracleAggregator.sol";
import {ITreasuryVault} from "../../contracts/solidity/interfaces/ITreasuryVault.sol";
import {Action, ActionKind, ProposalState} from "../../contracts/solidity/HelixTypes.sol";

/// @notice End-to-end integration test for the Helix proposal lifecycle.
///         Run against a forked Arbitrum Sepolia for realistic oracle / protocol conditions.
///
/// Usage:
///   forge test --match-contract HelixIntegrationTest -vvvv \
///     --fork-url $ARBITRUM_SEPOLIA_RPC
contract HelixIntegrationTest is Test {
    // ─── Actors ───
    address safe = makeAddr("safe");
    address guardian = makeAddr("guardian");
    address agent = makeAddr("agent");
    address alice = makeAddr("alice");  // treasury depositor

    // ─── Contracts ───
    TreasuryVault vault;
    PolicyRegistry policyRegistry;
    ProposalRegistry proposalRegistry;
    TaxEngine taxEngine;
    OracleAggregator oracle;

    // ─── Mock addresses (replaced with real on fork) ───
    address mockPolicyEngine;
    address mockChainlink = makeAddr("chainlink");
    address mockPyth = makeAddr("pyth");
    address mockUsdc = makeAddr("usdc");

    function setUp() public {
        // Deploy mock PolicyEngine (in integration: use real Stylus contract on fork)
        // TODO(mulerun): deploy MockPolicyEngine that always returns Approve
        mockPolicyEngine = makeAddr("policyEngine");

        // 1. OracleAggregator
        oracle = new OracleAggregator(mockChainlink, mockPyth, safe, guardian);

        // 2. PolicyRegistry with a trivial "approve everything" policy
        bytes memory trivialPolicy = abi.encode("trivial-policy-v1");
        bytes32[] memory noConstraints = new bytes32[](0);
        policyRegistry = new PolicyRegistry(
            safe, mockPolicyEngine, mockPolicyEngine, trivialPolicy, noConstraints
        );

        // 3. ProposalRegistry
        proposalRegistry = new ProposalRegistry(
            mockPolicyEngine,
            address(policyRegistry),
            safe,
            guardian
        );

        // 4. TreasuryVault
        vault = new TreasuryVault(
            safe, guardian,
            address(proposalRegistry),
            mockPolicyEngine,
            address(0),  // taxEngine wired after
            address(oracle)
        );

        // 5. TaxEngine
        taxEngine = new TaxEngine(safe, address(vault), bytes8(0) /* US jurisdiction */, 0 /* FIFO */);

        // 6. Wire vault and agent into ProposalRegistry
        vm.startPrank(safe);
        proposalRegistry.setVault(address(vault));
        proposalRegistry.setAuthorizedAgent(agent, true);
        vm.stopPrank();

        // 7. Register USDC as asset
        vm.prank(safe);
        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: mockUsdc,
            decimals: 6,
            isStable: true,
            isLiquid: true,
            protocol: ITreasuryVault.Protocol.WALLET,
            adapter: address(0),
            active: true
        }));
    }

    // ──────────── Test: full proposal lifecycle ────────────

    /// @notice Happy path: agent submits → Safe approves → timelock elapses → executed.
    function test_ProposalLifecycle_HappyPath() public {
        // TODO(mulerun): implement once PolicyEngine and TreasuryVault.executeApproved are complete.
        // Steps:
        // 1. alice deposits 1000 USDC into vault
        // 2. agent submits proposal: AAVE_SUPPLY 200 USDC
        // 3. assert proposalId emitted, state == PolicyAccepted
        // 4. vm.prank(safe); proposalRegistry.approveProposal(proposalId)
        // 5. vm.warp(block.timestamp + 1 hours + 1)
        // 6. proposalRegistry.executeProposal(proposalId)
        // 7. assert vault USDC balance decreased by 200
        // 8. assert TaxEngine recorded a SUPPLY event
        assertTrue(true, "placeholder");
    }

    /// @notice Hard reject: agent proposes action that breaches MAX_DAILY_MOVEMENT.
    function test_ProposalRejected_HardConstraintBreach() public {
        // TODO(mulerun): mock PolicyEngine to return HardReject for this specific action.
        // assert submitProposal reverts with "ProposalRegistry: hard reject"
        assertTrue(true, "placeholder");
    }

    /// @notice Emergency pause: guardian pauses vault; agent submission fails.
    function test_EmergencyPause() public {
        vm.prank(guardian);
        vault.emergencyPause();
        assertTrue(vault.paused(), "vault should be paused");

        // Agent cannot submit proposals while paused
        // TODO(mulerun): assert proposalRegistry.submitProposal reverts
    }

    /// @notice Timelock: execution before timelock expires reverts.
    function test_TimelockNotExpired_Reverts() public {
        // TODO(mulerun): submit + approve proposal, then immediately try to execute without warping.
        // assert executeProposal reverts with "ProposalRegistry: timelock active"
        assertTrue(true, "placeholder");
    }

    /// @notice Invariant: vault balance never decreases without an executed proposal.
    function invariant_VaultBalanceOnlyDecreasesOnExecution() public view {
        // Foundry invariant testing — called repeatedly by fuzzer
        // TODO(mulerun): track vault balance deltas, assert no unauthorized decrease
    }
}
