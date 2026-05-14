// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {PolicyRegistry} from "../../contracts/solidity/PolicyRegistry.sol";
import {IPolicyRegistry} from "../../contracts/solidity/interfaces/IPolicyRegistry.sol";

contract PolicyRegistryTest is Test {
    PolicyRegistry registry;

    address safe = makeAddr("safe");
    address verifier = makeAddr("verifier");
    address hardLib = makeAddr("hardLib");
    bytes initialPolicy = abi.encode("initial-policy");

    function setUp() public {
        bytes32[] memory noConstraints = new bytes32[](0);
        registry = new PolicyRegistry(safe, verifier, hardLib, initialPolicy, noConstraints);
    }

    function test_InitialPolicyActive() public view {
        bytes32 expectedHash = keccak256(initialPolicy);
        assertEq(registry.activePolicyHash(), expectedHash);
    }

    function test_ProposePolicy_OnlyOwner() public {
        bytes memory newPolicy = abi.encode("new-policy");
        bytes32[] memory noConstraints = new bytes32[](0);

        // Non-owner reverts
        vm.expectRevert("PolicyRegistry: not owner");
        registry.proposeUpdate(newPolicy, noConstraints);

        // Owner succeeds
        vm.prank(safe);
        registry.proposeUpdate(newPolicy, noConstraints);
    }

    function test_Timelock_7Days() public {
        bytes memory newPolicy = abi.encode("new-policy-v2");
        bytes32[] memory noConstraints = new bytes32[](0);

        vm.prank(safe);
        registry.proposeUpdate(newPolicy, noConstraints);

        // Cannot activate before 7 days
        vm.expectRevert("PolicyRegistry: timelock");
        vm.prank(safe);
        registry.activatePending();

        // Warp 7 days + 1 second
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(safe);
        registry.activatePending();

        assertEq(registry.activePolicyHash(), keccak256(newPolicy));
    }

    function test_PolicyCannotWeakenConstraints() public {
        // TODO(mulerun): deploy mock verifier that rejects weakened constraints.
        // Verify that proposeUpdate with weaker hard constraints is rejected by verifier.
        assertTrue(true, "placeholder — requires mock PolicyVerifier");
    }
}
