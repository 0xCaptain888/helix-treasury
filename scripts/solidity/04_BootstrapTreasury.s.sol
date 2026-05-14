// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TreasuryVault} from "../../contracts/solidity/TreasuryVault.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";
import {ITreasuryVault} from "../../contracts/solidity/interfaces/ITreasuryVault.sol";

/// @notice Phase 4: Bootstrap — register assets, authorize Execution Agent, install Safe module.
///         This is the final setup step. After this, the treasury is LIVE for agent operation.
///
/// WARNING: After this script, the Safe is fully wired. Any mistake in asset registration
///          or agent authorization is Safe-gated to fix. Double-check all addresses before running.
///
/// Usage:
///   export AGENT_ADDRESS=<execution_agent_eoa>
///   forge script scripts/solidity/04_BootstrapTreasury.s.sol --rpc-url $RPC_URL --broadcast
contract BootstrapTreasury is Script {
    using stdJson for string;

    // Arbitrum Sepolia token addresses
    address constant USDC_SEPOLIA   = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant WETH_SEPOLIA   = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;
    address constant ARB_SEPOLIA    = 0x9d04741a45E3ac6AB8E91e69E1aFb34dAB4aFBe3;
    // Robinhood Chain testnet — placeholder; update when testnet is live
    address constant RH_TBILL_SEPOLIA = address(0);

    function run() external {
        string memory phase3 = vm.readFile("./deployments/phase3.json");
        address vaultAddr = phase3.readAddress(".treasury_vault");
        address proposalRegistryAddr = phase3.readAddress(".proposal_registry");

        address agentAddress = vm.envAddress("AGENT_ADDRESS");
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");

        TreasuryVault vault = TreasuryVault(vaultAddr);
        ProposalRegistry proposals = ProposalRegistry(proposalRegistryAddr);

        console2.log("=== Helix Phase 4: Bootstrap ===");
        console2.log("Vault:", vaultAddr);
        console2.log("Agent:", agentAddress);

        vm.startBroadcast(deployerKey);

        // 1. Register assets
        //    In production: each registration is a Safe tx with 24h timelock.
        //    For testnet bootstrap: deployer is temporary Safe owner.

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: USDC_SEPOLIA,
            decimals: 6,
            isStable: true,
            isLiquid: true,
            protocol: ITreasuryVault.Protocol.WALLET,
            adapter: address(0),
            active: true
        }));
        console2.log("Registered: USDC");

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: WETH_SEPOLIA,
            decimals: 18,
            isStable: false,
            isLiquid: true,
            protocol: ITreasuryVault.Protocol.WALLET,
            adapter: address(0),
            active: true
        }));
        console2.log("Registered: WETH");

        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: ARB_SEPOLIA,
            decimals: 18,
            isStable: false,
            isLiquid: true,
            protocol: ITreasuryVault.Protocol.WALLET,
            adapter: address(0),
            active: true
        }));
        console2.log("Registered: ARB");

        if (RH_TBILL_SEPOLIA != address(0)) {
            vault.registerAsset(ITreasuryVault.AssetEntry({
                token: RH_TBILL_SEPOLIA,
                decimals: 18,
                isStable: false,
                isLiquid: false,  // T-bills have settlement delay
                protocol: ITreasuryVault.Protocol.RWA,
                adapter: address(0), // Robinhood adapter registered separately
                active: true
            }));
            console2.log("Registered: RH_TBILL");
        }

        // 2. Authorize Execution Agent
        proposals.setAuthorizedAgent(agentAddress, true);
        console2.log("Agent authorized:", agentAddress);

        vm.stopBroadcast();

        console2.log("=== Bootstrap complete ===");
        console2.log("Treasury is live. Start the Execution Agent:");
        console2.log("  cd agent && HELIX_CONFIG_PATH=./config.yaml pnpm start");
        console2.log("");
        console2.log("Verify deployment:");
        console2.log("  pnpm verify:deployment --network arbitrum-sepolia");
    }
}
