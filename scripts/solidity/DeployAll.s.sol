// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {OracleAggregator} from "../../contracts/solidity/OracleAggregator.sol";
import {PolicyRegistry} from "../../contracts/solidity/PolicyRegistry.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";
import {TreasuryVault} from "../../contracts/solidity/TreasuryVault.sol";
import {TaxEngine} from "../../contracts/solidity/TaxEngine.sol";
import {TreasuryFactory} from "../../contracts/solidity/TreasuryFactory.sol";
import {ERC20Adapter} from "../../contracts/solidity/adapters/ERC20Adapter.sol";
import {AaveAdapter} from "../../contracts/solidity/adapters/AaveAdapter.sol";
import {PendleAdapter} from "../../contracts/solidity/adapters/PendleAdapter.sol";
import {RobinhoodRWAAdapter} from "../../contracts/solidity/adapters/RobinhoodRWAAdapter.sol";
import {ITreasuryVault} from "../../contracts/solidity/interfaces/ITreasuryVault.sol";

/// @notice All-in-one deployment script for Helix on Arbitrum Sepolia.
///         Deploys all contracts, wires them together, registers assets, authorizes agent.
///         Uses deployer as Safe owner for testnet purposes.
contract DeployAll is Script {
    // Arbitrum Sepolia known addresses
    address constant CHAINLINK_ETH_USD = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;
    address constant CHAINLINK_USDC_USD = 0x0153002d20B96532C639313c2d54c3dA09109309;

    // Arbitrum Sepolia token addresses
    address constant USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    address constant WETH = 0x980B62Da83eFf3D4576C647993b0c1D7faf17c73;

    // Protocol addresses on Arbitrum Sepolia (placeholders for testnet)
    address constant UNISWAP_ROUTER = address(0x101); // placeholder
    address constant AAVE_POOL = address(0x102);      // placeholder
    address constant PENDLE_ROUTER = address(0x103);   // placeholder
    address constant RWA_EXCHANGE = address(0x104);    // placeholder

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");
        address agent = vm.envAddress("AGENT_ADDRESS");

        // For testnet: deployer acts as Safe owner
        address safe = deployer;

        console2.log("=== Helix Full Deployment ===");
        console2.log("Deployer / Safe:", deployer);
        console2.log("Guardian:", guardian);
        console2.log("Agent:", agent);
        console2.log("Chain ID:", block.chainid);
        console2.log("");

        vm.startBroadcast(deployerKey);

        // ─── Phase 1: Oracle ───
        console2.log("--- Phase 1: OracleAggregator ---");
        OracleAggregator oracle = new OracleAggregator(
            address(0), // chainlink registry (not needed for direct feeds)
            address(0), // pyth (not available on sepolia testnet)
            safe,
            guardian
        );
        console2.log("OracleAggregator:", address(oracle));

        // Set min sources to 1 for testnet (only Chainlink available)
        oracle.setMinSources(1);

        // ─── Phase 2: PolicyRegistry + ProposalRegistry ───
        console2.log("--- Phase 2: Registries ---");

        // Use a mock PolicyEngine address (Stylus not deployed yet)
        address mockPolicyEngine = address(0xBEEF);

        bytes memory initialPolicy = abi.encode("helix-default-policy-v1");
        bytes32[] memory noConstraints = new bytes32[](0);
        PolicyRegistry policyRegistry = new PolicyRegistry(
            safe,
            mockPolicyEngine,  // verifier
            mockPolicyEngine,  // hardConstraintsLib
            initialPolicy,
            noConstraints
        );
        console2.log("PolicyRegistry:", address(policyRegistry));
        console2.log("Active policy hash:", vm.toString(policyRegistry.activePolicyHash()));

        ProposalRegistry proposalRegistry = new ProposalRegistry(
            mockPolicyEngine,
            address(policyRegistry),
            safe,
            guardian
        );
        console2.log("ProposalRegistry:", address(proposalRegistry));

        // ─── Phase 3: TaxEngine + TreasuryVault ───
        console2.log("--- Phase 3: Vault + TaxEngine ---");

        TaxEngine taxEngine = new TaxEngine(
            safe,
            address(0),  // vault not yet known, will be set later or left as-is for testnet
            bytes8(uint64(0x5553)),  // "US"
            0  // FIFO
        );
        console2.log("TaxEngine:", address(taxEngine));

        TreasuryVault vault = new TreasuryVault(
            safe,
            guardian,
            address(proposalRegistry),
            mockPolicyEngine,
            address(taxEngine),
            address(oracle)
        );
        console2.log("TreasuryVault:", address(vault));

        // Wire ProposalRegistry → Vault
        proposalRegistry.setVault(address(vault));
        console2.log("ProposalRegistry.vault wired");

        // ─── Phase 4: Adapters ───
        console2.log("--- Phase 4: Adapters ---");

        ERC20Adapter erc20Adapter = new ERC20Adapter(
            address(vault), UNISWAP_ROUTER, guardian
        );
        console2.log("ERC20Adapter:", address(erc20Adapter));

        AaveAdapter aaveAdapter = new AaveAdapter(
            address(vault), AAVE_POOL, guardian
        );
        console2.log("AaveAdapter:", address(aaveAdapter));

        PendleAdapter pendleAdapter = new PendleAdapter(
            address(vault), PENDLE_ROUTER, guardian
        );
        console2.log("PendleAdapter:", address(pendleAdapter));

        RobinhoodRWAAdapter rwaAdapter = new RobinhoodRWAAdapter(
            address(vault), RWA_EXCHANGE, address(taxEngine), guardian
        );
        console2.log("RobinhoodRWAAdapter:", address(rwaAdapter));

        // ─── Phase 5: Bootstrap ───
        console2.log("--- Phase 5: Bootstrap ---");

        // Register USDC
        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: USDC,
            tokenType: 1,
            adapter: bytes32(0),
            active: true,
            registeredAt: 0
        }));
        console2.log("Registered: USDC");

        // Register WETH
        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: WETH,
            tokenType: 0,
            adapter: bytes32(0),
            active: true,
            registeredAt: 0
        }));
        console2.log("Registered: WETH");

        // Authorize agent
        proposalRegistry.setAuthorizedAgent(agent, true);
        console2.log("Agent authorized:", agent);

        vm.stopBroadcast();

        // ─── Summary ───
        console2.log("");
        console2.log("========================================");
        console2.log("  DEPLOYMENT COMPLETE");
        console2.log("========================================");
        console2.log("OracleAggregator:    ", address(oracle));
        console2.log("PolicyRegistry:      ", address(policyRegistry));
        console2.log("ProposalRegistry:    ", address(proposalRegistry));
        console2.log("TreasuryVault:       ", address(vault));
        console2.log("TaxEngine:           ", address(taxEngine));
        console2.log("ERC20Adapter:        ", address(erc20Adapter));
        console2.log("AaveAdapter:         ", address(aaveAdapter));
        console2.log("PendleAdapter:       ", address(pendleAdapter));
        console2.log("RobinhoodRWAAdapter: ", address(rwaAdapter));
        console2.log("========================================");

        // Write deployment JSON
        string memory json = string.concat(
            '{"chain_id":421614,',
            '"deployer":"', vm.toString(deployer), '",',
            '"safe":"', vm.toString(safe), '",',
            '"guardian":"', vm.toString(guardian), '",',
            '"agent":"', vm.toString(agent), '",',
            '"oracle_aggregator":"', vm.toString(address(oracle)), '",',
            '"policy_registry":"', vm.toString(address(policyRegistry)), '",',
            '"proposal_registry":"', vm.toString(address(proposalRegistry)), '",',
            '"treasury_vault":"', vm.toString(address(vault)), '",',
            '"tax_engine":"', vm.toString(address(taxEngine)), '",',
            '"erc20_adapter":"', vm.toString(address(erc20Adapter)), '",',
            '"aave_adapter":"', vm.toString(address(aaveAdapter)), '",',
            '"pendle_adapter":"', vm.toString(address(pendleAdapter)), '",',
            '"rwa_adapter":"', vm.toString(address(rwaAdapter)), '",',
            '"policy_engine_mock":"', vm.toString(mockPolicyEngine), '"}'
        );
        vm.writeFile("./deployments/deployment.json", json);
        console2.log("Deployment addresses saved to deployments/deployment.json");
    }
}
