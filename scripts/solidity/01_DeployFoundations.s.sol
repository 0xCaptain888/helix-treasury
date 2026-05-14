// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {OracleAggregator} from "../../contracts/solidity/OracleAggregator.sol";

/// @notice Phase 1: Deploy oracle infrastructure only.
///         PolicyEngine (Stylus) is deployed separately via `cargo stylus deploy`.
///         Run this after Stylus deployment; pass the Stylus address as env var.
///
/// Usage:
///   export DEPLOYER_KEY=<private_key>
///   export SAFE_ADDRESS=<safe_address>
///   export GUARDIAN_ADDRESS=<guardian_address>
///   export CHAINLINK_REGISTRY=<chainlink_registry>
///   export PYTH_ADDRESS=<pyth_address>
///   forge script scripts/solidity/01_DeployFoundations.s.sol --rpc-url $RPC_URL --broadcast --verify
contract DeployFoundations is Script {
    function run() external {
        address safe = vm.envAddress("SAFE_ADDRESS");
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");
        address chainlinkRegistry = vm.envAddress("CHAINLINK_REGISTRY");
        address pyth = vm.envAddress("PYTH_ADDRESS");

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("=== Helix Phase 1: Foundations ===");
        console2.log("Deployer:", deployer);
        console2.log("Safe:", safe);
        console2.log("Guardian:", guardian);

        vm.startBroadcast(deployerKey);

        // 1. OracleAggregator
        OracleAggregator oracle = new OracleAggregator(
            chainlinkRegistry,
            pyth,
            safe,
            guardian
        );
        console2.log("OracleAggregator deployed:", address(oracle));

        // 2. Register initial feeds (Arbitrum Sepolia addresses)
        // USDC/USD — Chainlink: 0x0153002d20B96532C639313c2d54c3dA09109309
        oracle.setChainlinkFeed(
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831, // USDC on Arb One (use testnet addr in practice)
            0x0153002d20B96532C639313c2d54c3dA09109309  // Chainlink USDC/USD Arb Sepolia
        );
        // ETH/USD — Chainlink: 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165
        oracle.setChainlinkFeed(
            0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH
            0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165  // Chainlink ETH/USD Arb Sepolia
        );

        vm.stopBroadcast();

        // Write addresses to JSON for next script phase
        string memory json = string.concat(
            '{"oracle_aggregator":"', vm.toString(address(oracle)), '"}'
        );
        vm.writeFile("./deployments/phase1.json", json);
        console2.log("Addresses written to deployments/phase1.json");
        console2.log("Next: deploy PolicyEngine via `cargo stylus deploy`, then run 02_DeployRegistry.s.sol");
    }
}
