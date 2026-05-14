// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {PolicyRegistry} from "../../contracts/solidity/PolicyRegistry.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";

/// @notice Phase 2: Deploy PolicyRegistry and ProposalRegistry.
///         Requires: phase1.json (OracleAggregator address) and Stylus PolicyEngine address.
///
/// Usage:
///   export POLICY_ENGINE_ADDRESS=<stylus_contract_address>
///   export INITIAL_POLICY_BYTECODE=<hex_bytes>  (from: helix-policy compile dao-quarterly-treasury.json)
///   forge script scripts/solidity/02_DeployRegistry.s.sol --rpc-url $RPC_URL --broadcast --verify
contract DeployRegistry is Script {
    using stdJson for string;

    function run() external {
        address safe = vm.envAddress("SAFE_ADDRESS");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");
        address policyEngine = vm.envAddress("POLICY_ENGINE_ADDRESS");
        bytes memory initialPolicy = vm.envBytes("INITIAL_POLICY_BYTECODE");

        // Load phase1 outputs
        string memory phase1 = vm.readFile("./deployments/phase1.json");
        address oracle = phase1.readAddress(".oracle_aggregator");

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(deployerKey);

        // 1. PolicyRegistry
        //    Verifier and hardConstraintsLib — use PolicyEngine address as verifier for now.
        //    In production: deploy a standalone PolicyVerifier contract.
        bytes32[] memory noHardConstraints = new bytes32[](0);
        PolicyRegistry registry = new PolicyRegistry(
            safe,           // owner (Safe multisig)
            policyEngine,   // verifier
            policyEngine,   // hardConstraintsLib (Stylus provides both)
            initialPolicy,
            noHardConstraints
        );
        console2.log("PolicyRegistry deployed:", address(registry));
        console2.log("Active policy hash:", vm.toString(registry.activePolicyHash()));

        // 2. ProposalRegistry
        ProposalRegistry proposals = new ProposalRegistry(
            policyEngine,
            address(registry),
            safe,
            guardian
        );
        console2.log("ProposalRegistry deployed:", address(proposals));
        console2.log("Timelock:", proposals.executionTimelock());

        vm.stopBroadcast();

        string memory json = string.concat(
            '{"oracle_aggregator":"', vm.toString(oracle),
            '","policy_registry":"', vm.toString(address(registry)),
            '","proposal_registry":"', vm.toString(address(proposals)),
            '","policy_engine":"', vm.toString(policyEngine), '"}'
        );
        vm.writeFile("./deployments/phase2.json", json);
        console2.log("Addresses written to deployments/phase2.json");
        console2.log("Next: run 03_DeployVault.s.sol");
    }
}
