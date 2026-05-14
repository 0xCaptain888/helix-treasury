// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TreasuryVault} from "../../contracts/solidity/TreasuryVault.sol";
import {TaxEngine} from "../../contracts/solidity/TaxEngine.sol";

/// @notice Phase 3: Deploy TreasuryVault + TaxEngine.
///         Note: TreasuryFactory.deployTreasury is not yet fully implemented;
///         individual deployment is used here until the factory is complete.
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

        // 1. Deploy TaxEngine
        TaxEngine tax = new TaxEngine(
            safe,
            address(0), // vault not yet known
            bytes8("US-FIFO"),
            0 // FIFO
        );
        console2.log("TaxEngine deployed:", address(tax));

        // 2. Deploy TreasuryVault
        TreasuryVault vault = new TreasuryVault(
            safe,
            guardian,
            proposalRegistry,
            policyEngine,
            address(tax),
            oracle
        );
        console2.log("TreasuryVault deployed:", address(vault));

        // 3. Wire ProposalRegistry → Vault
        console2.log("TODO: Wire ProposalRegistry vault address via Safe tx");
        console2.log("Call ProposalRegistry.setVault(", address(vault), ") from Safe:", safe);

        vm.stopBroadcast();

        string memory json = string.concat(
            '{"oracle_aggregator":"', vm.toString(oracle),
            '","policy_registry":"', vm.toString(policyRegistry),
            '","proposal_registry":"', vm.toString(proposalRegistry),
            '","policy_engine":"', vm.toString(policyEngine),
            '","treasury_vault":"', vm.toString(address(vault)),
            '","tax_engine":"', vm.toString(address(tax)), '"}'
        );
        vm.writeFile("./deployments/phase3.json", json);
        console2.log("All addresses written to deployments/phase3.json");
        console2.log("Next: run 04_BootstrapTreasury.s.sol to register assets + authorize agent");
    }
}
