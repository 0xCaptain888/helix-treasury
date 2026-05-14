// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TreasuryFactory} from "../../contracts/solidity/TreasuryFactory.sol";

/// @notice Phase 3: Deploy TreasuryVault + TaxEngine via TreasuryFactory.
///         TreasuryFactory atomically deploys both and wires them together.
///         Also wires ProposalRegistry → Vault (completes the circular reference via setter).
///
/// Usage:
///   forge script scripts/solidity/03_DeployVault.s.sol --rpc-url $RPC_URL --broadcast --verify
contract DeployVault is Script {
    using stdJson for string;

    function run() external {
        address safe = vm.envAddress("SAFE_ADDRESS");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");

        string memory phase2 = vm.readFile("./deployments/phase2.json");
        address policyEngine = phase2.readAddress(".policy_engine");
        address policyRegistry = phase2.readAddress(".policy_registry");
        address proposalRegistry = phase2.readAddress(".proposal_registry");
        address oracle = phase2.readAddress(".oracle_aggregator");

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        vm.startBroadcast(deployerKey);

        // 1. Deploy TreasuryFactory (pass immutable infrastructure addresses)
        TreasuryFactory factory = new TreasuryFactory(
            policyEngine,
            policyEngine,      // verifier (Stylus provides both)
            policyEngine,      // hardConstraintsLib
            oracle
        );
        console2.log("TreasuryFactory deployed:", address(factory));

        // 2. Deploy treasury suite atomically
        TreasuryFactory.TreasuryConfig memory cfg = TreasuryFactory.TreasuryConfig({
            safe: safe,
            guardian: guardian,
            proposalRegistry: proposalRegistry,
            policyEngine: policyEngine,
            policyRegistry: policyRegistry,
            oracleAggregator: oracle,
            defaultJurisdiction: 0 // US_FIFO
        });

        (address vault, address taxEngine) = factory.deploy(cfg);
        console2.log("TreasuryVault deployed:", vault);
        console2.log("TaxEngine deployed:", taxEngine);

        // 3. Wire ProposalRegistry → Vault (Safe-gated call via forge broadcast)
        //    NOTE: This requires the Safe to execute this transaction.
        //    In practice: generate Safe tx here, execute via Safe SDK or Gnosis UI.
        //    For testnet: deployer is temporary Safe owner.
        console2.log("TODO: Wire ProposalRegistry vault address via Safe tx");
        console2.log("Call ProposalRegistry.setVault(", vault, ") from Safe:", safe);

        vm.stopBroadcast();

        string memory json = string.concat(
            '{"oracle_aggregator":"', vm.toString(oracle),
            '","policy_registry":"', vm.toString(policyRegistry),
            '","proposal_registry":"', vm.toString(proposalRegistry),
            '","policy_engine":"', vm.toString(policyEngine),
            '","treasury_vault":"', vm.toString(vault),
            '","tax_engine":"', vm.toString(taxEngine),
            '","treasury_factory":"', vm.toString(address(factory)), '"}'
        );
        vm.writeFile("./deployments/phase3.json", json);
        console2.log("All addresses written to deployments/phase3.json");
        console2.log("Next: run 04_BootstrapTreasury.s.sol to register assets + authorize agent");
    }
}
