// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PolicyRegistry} from "./PolicyRegistry.sol";
import {ProposalRegistry} from "./ProposalRegistry.sol";
import {TreasuryVault} from "./TreasuryVault.sol";
import {TaxEngine} from "./TaxEngine.sol";

/// @title TreasuryFactory
/// @notice One-shot atomic deployment of a complete Helix treasury (vault + tax engine).
///         PolicyRegistry and ProposalRegistry are deployed separately in Phase 2.
/// @dev See docs/04-contracts.md §8.
contract TreasuryFactory {
    struct TreasuryConfig {
        address safe;
        address guardian;
        address proposalRegistry;
        address policyEngine;
        address policyRegistry;
        address oracleAggregator;
        uint8 defaultJurisdiction; // 0=US_FIFO
    }

    address public immutable engine;
    address public immutable verifier;
    address public immutable hardConstraintsLib;
    address public immutable oracleAggregator;

    event TreasuryDeployed(
        address indexed safe,
        address indexed vault,
        address taxEngine
    );

    constructor(address _engine, address _verifier, address _hardConstraintsLib, address _oracleAggregator) {
        engine = _engine;
        verifier = _verifier;
        hardConstraintsLib = _hardConstraintsLib;
        oracleAggregator = _oracleAggregator;
    }

    function deploy(TreasuryConfig calldata cfg)
        external
        returns (address vault, address taxEngineAddr)
    {
        require(cfg.safe != address(0) && cfg.guardian != address(0), "Factory: zero addr");

        // 1. Deploy TaxEngine (with a temporary vault address of address(0),
        //    then wire it after vault deployment via CREATE2 precomputation or setter pattern)
        TaxEngine tax = new TaxEngine(
            cfg.safe,
            address(0), // vault not yet known
            bytes8(uint64(cfg.defaultJurisdiction)),
            0 // FIFO default
        );
        taxEngineAddr = address(tax);

        // 2. Deploy TreasuryVault
        TreasuryVault v = new TreasuryVault(
            cfg.safe,
            cfg.guardian,
            cfg.proposalRegistry,
            cfg.policyEngine,
            taxEngineAddr,
            cfg.oracleAggregator
        );
        vault = address(v);

        emit TreasuryDeployed(cfg.safe, vault, taxEngineAddr);
    }
}
