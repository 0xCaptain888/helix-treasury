// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PolicyRegistry} from "./PolicyRegistry.sol";
import {ProposalRegistry} from "./ProposalRegistry.sol";
import {TreasuryVault} from "./TreasuryVault.sol";
import {TaxEngine} from "./TaxEngine.sol";

/// @title TreasuryFactory
/// @notice One-shot atomic deployment of a complete Helix treasury (vault + registries + tax).
/// @dev See docs/04-contracts.md §8.
contract TreasuryFactory {
    struct DeployConfig {
        address safe;
        address guardian;
        bytes32 initialPolicyHash;
        bytes initialPolicyBytecode;
        bytes32[] hardConstraintIds;
        bytes8 jurisdiction;
        uint8 lotMethod;
        address[] initialAssets;
        address[] authorizedAgents;
    }

    address public immutable engine; // shared PolicyEngine (Stylus)
    address public immutable verifier;
    address public immutable hardConstraintsLib;
    address public immutable oracleAggregator;

    event TreasuryDeployed(
        address indexed safe,
        address indexed vault,
        address policyRegistry,
        address proposalRegistry,
        address taxEngine
    );

    constructor(address _engine, address _verifier, address _hardConstraintsLib, address _oracleAggregator) {
        engine = _engine;
        verifier = _verifier;
        hardConstraintsLib = _hardConstraintsLib;
        oracleAggregator = _oracleAggregator;
    }

    function deployTreasury(DeployConfig calldata cfg)
        external
        returns (address vault, address policyRegistryAddr, address proposalRegistryAddr, address taxEngineAddr)
    {
        require(cfg.safe != address(0) && cfg.guardian != address(0), "Factory: zero addr");

        // 1. Deploy PolicyRegistry
        policyRegistryAddr = address(new PolicyRegistry(
            cfg.safe,
            verifier,
            hardConstraintsLib,
            cfg.initialPolicyBytecode,
            cfg.hardConstraintIds
        ));

        // 2. Deploy ProposalRegistry
        proposalRegistryAddr = address(new ProposalRegistry(engine, policyRegistryAddr, cfg.safe, cfg.guardian));

        // 3. Deploy TaxEngine (vault address will be set in step 5 reverse wiring)
        // TODO(mulerun): TaxEngine needs vault address; either use CREATE2 with precomputed address
        // or implement a setVault one-shot initializer.

        // 4. Deploy TreasuryVault
        // TODO(mulerun): vault = new TreasuryVault(cfg.safe, cfg.guardian, proposalRegistryAddr, engine, taxEngineAddr, oracleAggregator);

        // 5. Wire ProposalRegistry.setVault(vault)
        // 6. Register initial assets
        // 7. Register initial authorized agents
        // 8. Emit TreasuryDeployed

        revert("TreasuryFactory: not implemented");
    }
}
