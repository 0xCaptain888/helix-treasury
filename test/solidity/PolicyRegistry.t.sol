// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {PolicyRegistry} from "../../contracts/solidity/PolicyRegistry.sol";
import {IPolicyRegistry} from "../../contracts/solidity/interfaces/IPolicyRegistry.sol";

contract PolicyRegistryTest is Test {
    PolicyRegistry registry;

    address safe     = makeAddr("safe");
    address verifier = makeAddr("verifier");
    address hardLib  = makeAddr("hardLib");

    bytes constant INITIAL_POLICY = hex"48454c5800000001";

    function setUp() public {
        bytes32[] memory noConstraints = new bytes32[](0);
        registry = new PolicyRegistry(safe, verifier, hardLib, INITIAL_POLICY, noConstraints);
    }

    function test_InitialPolicyActive() public view {
        bytes32 expectedHash = keccak256(INITIAL_POLICY);
        assertEq(registry.activePolicyHash(), expectedHash);
    }

    function test_OwnerIsSet() public view {
        assertEq(registry.owner(), safe);
    }

    function test_GetActivePolicy() public view {
        (bytes32 hash, IPolicyRegistry.PolicyMeta memory meta) = registry.activePolicy();
        assertEq(hash, keccak256(INITIAL_POLICY));
        assertTrue(meta.active);
        assertEq(meta.author, safe);
    }

    function test_GetPolicyBytecode() public view {
        (bytes memory bytecode,) = registry.getPolicy(keccak256(INITIAL_POLICY));
        assertEq(bytecode, INITIAL_POLICY);
    }

    function test_ProposeUpdate_OnlyOwner() public {
        bytes memory newPolicy = abi.encodePacked(hex"48454c58", uint32(2));
        vm.expectRevert("PolicyRegistry: not owner");
        registry.proposeUpdate(newPolicy);
    }

    function test_ProposeUpdate_SetsHash() public {
        bytes memory newPolicy = abi.encodePacked(hex"48454c58", uint32(2), uint256(42));
        vm.prank(safe);
        bytes32 newHash = registry.proposeUpdate(newPolicy);
        assertEq(newHash, keccak256(newPolicy));
        assertEq(registry.pendingPolicyHash(), newHash);
    }

    function test_ProposeUpdate_EmptyReverts() public {
        vm.expectRevert("PolicyRegistry: empty bytecode");
        vm.prank(safe);
        registry.proposeUpdate(bytes(""));
    }

    function test_ProposeUpdate_SamePolicyReverts() public {
        vm.expectRevert("PolicyRegistry: same policy");
        vm.prank(safe);
        registry.proposeUpdate(INITIAL_POLICY);
    }

    function test_ActivateUpdate_BeforeTimelockReverts() public {
        bytes memory newPolicy = abi.encodePacked(hex"48454c58", uint32(99));
        vm.prank(safe);
        bytes32 newHash = registry.proposeUpdate(newPolicy);

        vm.expectRevert("PolicyRegistry: timelock not expired");
        vm.prank(safe);
        registry.activateUpdate(newHash);
    }

    function test_ActivateUpdate_AfterTimelock() public {
        bytes memory newPolicy = abi.encodePacked(hex"48454c58", uint32(99), uint256(1));
        vm.prank(safe);
        bytes32 newHash = registry.proposeUpdate(newPolicy);

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(safe);
        registry.activateUpdate(newHash);

        assertEq(registry.activePolicyHash(), newHash);
        assertTrue(registry.pendingPolicyHash() == bytes32(0));
    }

    function test_ActivateUpdate_WrongHashReverts() public {
        bytes memory newPolicy = abi.encodePacked(hex"48454c58", uint32(77));
        vm.prank(safe);
        registry.proposeUpdate(newPolicy);

        vm.warp(block.timestamp + 7 days + 1);
        vm.expectRevert("PolicyRegistry: not pending");
        vm.prank(safe);
        registry.activateUpdate(bytes32(uint256(0xdead)));
    }

    function test_ActivateUpdate_OldPolicyDeactivated() public {
        bytes32 oldHash = registry.activePolicyHash();
        bytes memory newPolicy = abi.encodePacked(hex"48454c58", uint32(88), uint256(2));
        vm.prank(safe);
        bytes32 newHash = registry.proposeUpdate(newPolicy);

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(safe);
        registry.activateUpdate(newHash);

        (, IPolicyRegistry.PolicyMeta memory oldMeta) = registry.getPolicy(oldHash);
        assertFalse(oldMeta.active);
    }

    function test_GetHardConstraints_Empty() public view {
        bytes32[] memory ids = registry.getHardConstraints(registry.activePolicyHash());
        assertEq(ids.length, 0);
    }

    function testFuzz_ProposeAndActivate(bytes calldata policyData) public {
        vm.assume(policyData.length > 4);
        vm.assume(keccak256(policyData) != keccak256(INITIAL_POLICY));

        vm.prank(safe);
        bytes32 newHash = registry.proposeUpdate(policyData);
        assertEq(registry.pendingPolicyHash(), newHash);

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(safe);
        registry.activateUpdate(newHash);

        assertEq(registry.activePolicyHash(), newHash);
    }
}
