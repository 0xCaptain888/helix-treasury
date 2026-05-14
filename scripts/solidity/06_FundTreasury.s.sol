// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {TreasuryVault} from "../../contracts/solidity/TreasuryVault.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Phase 6: Fund the treasury with initial assets for testing.
///         Deposits USDC into the vault and posts an initial bond for the agent.
///         Requires: phase3.json (TreasuryVault, ProposalRegistry addresses).
///
/// Usage:
///   export DEPLOYER_KEY=<private_key>
///   export USDC_ADDRESS=<usdc_token_address>  (optional, defaults to Arbitrum Sepolia USDC)
///   forge script scripts/solidity/06_FundTreasury.s.sol --rpc-url $RPC_URL --broadcast
contract FundTreasury is Script {
    using stdJson for string;

    // Default: Arbitrum Sepolia USDC
    address constant DEFAULT_USDC = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;

    // Initial deposit amount: 1000 USDC (6 decimals)
    uint256 constant USDC_DEPOSIT_AMOUNT = 1_000e6;

    // Bond amount for agent
    uint256 constant BOND_AMOUNT = 0.01 ether;

    function run() external {
        // Load phase3 outputs
        string memory phase3 = vm.readFile("./deployments/phase3.json");
        address vaultAddr = phase3.readAddress(".treasury_vault");
        address proposalRegistryAddr = phase3.readAddress(".proposal_registry");

        // USDC address: env var or default
        address usdc = vm.envOr("USDC_ADDRESS", DEFAULT_USDC);

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);

        TreasuryVault vault = TreasuryVault(vaultAddr);
        ProposalRegistry proposals = ProposalRegistry(proposalRegistryAddr);
        IERC20 usdcToken = IERC20(usdc);

        console2.log("=== Helix Phase 6: Fund Treasury ===");
        console2.log("Deployer:", deployer);
        console2.log("Vault:", vaultAddr);
        console2.log("ProposalRegistry:", proposalRegistryAddr);
        console2.log("USDC:", usdc);
        console2.log("USDC deposit amount:", USDC_DEPOSIT_AMOUNT);
        console2.log("Bond amount:", BOND_AMOUNT);

        vm.startBroadcast(deployerKey);

        // 1. Approve vault to spend deployer's USDC
        usdcToken.approve(vaultAddr, USDC_DEPOSIT_AMOUNT);
        console2.log("Approved vault for USDC spend");

        // 2. Deposit USDC into vault
        vault.deposit(usdc, USDC_DEPOSIT_AMOUNT);
        console2.log("Deposited USDC into vault:", USDC_DEPOSIT_AMOUNT);

        // 3. Fund agent with bond for proposal posting
        proposals.postBond{value: BOND_AMOUNT}();
        console2.log("Posted agent bond:", BOND_AMOUNT);

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== Treasury Funded ===");
        console2.log("USDC deposited:", USDC_DEPOSIT_AMOUNT);
        console2.log("Agent bond posted:", BOND_AMOUNT);
        console2.log("");
        console2.log("Treasury is ready for testing. Start the Execution Agent:");
        console2.log("  cd agent && HELIX_CONFIG_PATH=./config.yaml pnpm start");
    }
}
