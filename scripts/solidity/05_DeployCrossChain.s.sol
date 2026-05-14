// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {ERC20Adapter} from "../../contracts/solidity/adapters/ERC20Adapter.sol";
import {AaveAdapter} from "../../contracts/solidity/adapters/AaveAdapter.sol";
import {PendleAdapter} from "../../contracts/solidity/adapters/PendleAdapter.sol";
import {RobinhoodRWAAdapter} from "../../contracts/solidity/adapters/RobinhoodRWAAdapter.sol";

/// @notice Phase 5: Deploy cross-chain adapters and Robinhood RWA integration components.
///         Requires: phase3.json (TreasuryVault, TaxEngine addresses).
///
/// Usage:
///   export GUARDIAN_ADDRESS=<guardian_address>
///   export DEPLOYER_KEY=<private_key>
///   export UNISWAP_ROUTER=<uniswap_v3_router>
///   export AAVE_POOL=<aave_v3_pool>
///   export PENDLE_ROUTER=<pendle_router>
///   export RWA_EXCHANGE=<robinhood_rwa_exchange>
///   forge script scripts/solidity/05_DeployCrossChain.s.sol --rpc-url $RPC_URL --broadcast --verify
contract DeployCrossChain is Script {
    using stdJson for string;

    function run() external {
        address guardian = vm.envAddress("GUARDIAN_ADDRESS");
        address uniswapRouter = vm.envAddress("UNISWAP_ROUTER");
        address aavePool = vm.envAddress("AAVE_POOL");
        address pendleRouter = vm.envAddress("PENDLE_ROUTER");
        address rwaExchange = vm.envAddress("RWA_EXCHANGE");

        // Load phase3 outputs
        string memory phase3 = vm.readFile("./deployments/phase3.json");
        address vault = phase3.readAddress(".treasury_vault");
        address taxEngine = phase3.readAddress(".tax_engine");

        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("=== Helix Phase 5: Cross-Chain Adapters ===");
        console2.log("Deployer:", deployer);
        console2.log("Vault:", vault);
        console2.log("TaxEngine:", taxEngine);
        console2.log("Guardian:", guardian);

        vm.startBroadcast(deployerKey);

        // 1. ERC20Adapter (Uniswap V3 swaps)
        ERC20Adapter erc20Adapter = new ERC20Adapter(vault, uniswapRouter, guardian);
        console2.log("ERC20Adapter deployed:", address(erc20Adapter));

        // 2. AaveAdapter (Aave V3 supply/withdraw/borrow/repay)
        AaveAdapter aaveAdapter = new AaveAdapter(vault, aavePool, guardian);
        console2.log("AaveAdapter deployed:", address(aaveAdapter));

        // 3. PendleAdapter (PT/YT trading and redemption)
        PendleAdapter pendleAdapter = new PendleAdapter(vault, pendleRouter, guardian);
        console2.log("PendleAdapter deployed:", address(pendleAdapter));

        // 4. RobinhoodRWAAdapter (tokenized equities, ETFs, Treasuries)
        RobinhoodRWAAdapter rwaAdapter = new RobinhoodRWAAdapter(vault, rwaExchange, taxEngine, guardian);
        console2.log("RobinhoodRWAAdapter deployed:", address(rwaAdapter));

        vm.stopBroadcast();

        // Write addresses to JSON for reference
        string memory json = string.concat(
            '{"erc20_adapter":"', vm.toString(address(erc20Adapter)),
            '","aave_adapter":"', vm.toString(address(aaveAdapter)),
            '","pendle_adapter":"', vm.toString(address(pendleAdapter)),
            '","robinhood_rwa_adapter":"', vm.toString(address(rwaAdapter)),
            '","vault":"', vm.toString(vault),
            '","tax_engine":"', vm.toString(taxEngine), '"}'
        );
        vm.writeFile("./deployments/phase5.json", json);
        console2.log("Addresses written to deployments/phase5.json");

        console2.log("");
        console2.log("=== Next steps ===");
        console2.log("1. Register each adapter in TreasuryVault via vault.registerAsset() with the adapter address");
        console2.log("2. Authorize adapters in TaxEngine if needed");
        console2.log("3. Run 06_FundTreasury.s.sol to deposit initial test assets");
    }
}
