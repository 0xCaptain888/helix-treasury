// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {TreasuryVault} from "../../contracts/solidity/TreasuryVault.sol";
import {PolicyRegistry} from "../../contracts/solidity/PolicyRegistry.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";
import {TaxEngine} from "../../contracts/solidity/TaxEngine.sol";
import {OracleAggregator} from "../../contracts/solidity/OracleAggregator.sol";
import {ITreasuryVault} from "../../contracts/solidity/interfaces/ITreasuryVault.sol";
import {IProposalRegistry} from "../../contracts/solidity/interfaces/IProposalRegistry.sol";
import {Action, ActionKind, ProposalState, Verdict, VerdictKind} from "../../contracts/solidity/HelixTypes.sol";

contract MockPolicyEngine {
    function evaluate(
        bytes32 policyHash,
        bytes calldata, bytes calldata, bytes calldata
    ) external pure returns (bytes memory) {
        return abi.encodePacked(
            uint256(0),
            policyHash,
            bytes32(0),
            bytes32(0),
            uint256(0),
            uint256(0)
        );
    }
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name; symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract HelixIntegrationTest is Test {
    address safe     = makeAddr("safe");
    address guardian = makeAddr("guardian");
    address agent    = makeAddr("agent");
    address alice    = makeAddr("alice");

    TreasuryVault    vault;
    PolicyRegistry   policyRegistry;
    ProposalRegistry proposalRegistry;
    TaxEngine        taxEngine;
    MockPolicyEngine mockEngine;
    MockERC20        usdc;

    function setUp() public {
        usdc = new MockERC20("Mock USDC", "mUSDC");
        mockEngine = new MockPolicyEngine();

        bytes memory initialPolicy = abi.encodePacked(
            hex"48454c58", uint32(1),
            address(safe)
        );
        bytes32[] memory noConstraints = new bytes32[](0);
        policyRegistry = new PolicyRegistry(
            safe,
            address(mockEngine),
            address(mockEngine),
            initialPolicy,
            noConstraints
        );

        proposalRegistry = new ProposalRegistry(
            address(mockEngine),
            address(policyRegistry),
            safe,
            guardian
        );

        vault = new TreasuryVault(
            safe,
            guardian,
            address(proposalRegistry),
            address(mockEngine),
            address(0),
            address(0)
        );

        taxEngine = new TaxEngine(safe, address(vault), bytes8("US-FIFO"), 0);

        vm.prank(safe);
        proposalRegistry.setVault(address(vault));

        vm.prank(safe);
        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: address(usdc),
            tokenType: 0,
            adapter: bytes32(0),
            active: true,
            registeredAt: uint64(block.timestamp)
        }));

        vm.prank(safe);
        proposalRegistry.setAuthorizedAgent(agent, true);

        vm.deal(agent, 1 ether);
        vm.prank(agent);
        proposalRegistry.postBond{value: 0.1 ether}();
    }

    function test_Deposit_USDC() public {
        usdc.mint(alice, 1_000_000e18);
        vm.prank(alice);
        usdc.approve(address(vault), 1_000_000e18);
        vm.prank(alice);
        vault.deposit(address(usdc), 1_000_000e18);

        assertEq(usdc.balanceOf(address(vault)), 1_000_000e18);
    }

    function test_Deposit_UnregisteredAsset_Reverts() public {
        MockERC20 rando = new MockERC20("Rando", "RND");
        rando.mint(alice, 1000e18);
        vm.prank(alice);
        rando.approve(address(vault), 1000e18);
        vm.expectRevert("TreasuryVault: asset not registered");
        vm.prank(alice);
        vault.deposit(address(rando), 1000e18);
    }

    function test_Deposit_Zero_Reverts() public {
        vm.expectRevert("TreasuryVault: zero amount");
        vm.prank(alice);
        vault.deposit(address(usdc), 0);
    }

    function test_SubmitProposal_Unauthorized_Reverts() public {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            kind: ActionKind.TRANSFER,
            adapter: address(0),
            asset: address(usdc),
            amount: 100e18,
            params: abi.encode(alice)
        });
        bytes32 ph = policyRegistry.activePolicyHash();
        vm.expectRevert("ProposalRegistry: agent not authorized");
        vm.prank(alice);
        proposalRegistry.submitProposal(ph, bytes32(0), actions, bytes32(0), bytes(""));
    }

    function test_SubmitProposal_NoBond_Reverts() public {
        address newAgent = makeAddr("newAgent");
        vm.prank(safe);
        proposalRegistry.setAuthorizedAgent(newAgent, true);

        Action[] memory actions = _makeTransferAction(100e18);
        bytes32 ph = policyRegistry.activePolicyHash();
        vm.expectRevert("ProposalRegistry: insufficient bond");
        vm.prank(newAgent);
        proposalRegistry.submitProposal(ph, bytes32(0), actions, bytes32(0), bytes(""));
    }

    function test_SubmitProposal_Approved_Engine() public {
        _depositUsdc(1_000_000e18);
        Action[] memory actions = _makeTransferAction(100e18);

        bytes32 ph = policyRegistry.activePolicyHash();
        vm.prank(agent);
        bytes32 proposalId = proposalRegistry.submitProposal(
            ph, bytes32(0), actions, bytes32(0), bytes("")
        );

        IProposalRegistry.Proposal memory p = proposalRegistry.getProposal(proposalId);
        assertEq(uint8(p.state), uint8(ProposalState.Pending));
        assertEq(p.agent, agent);
    }

    function test_ApproveProposal_OnlySafe() public {
        _depositUsdc(1_000_000e18);
        bytes32 pid = _submitTransfer(100e18);

        vm.expectRevert("ProposalRegistry: not safe");
        vm.prank(alice);
        proposalRegistry.approveProposal(pid);
    }

    function test_ApproveProposal_SetsState() public {
        _depositUsdc(1_000_000e18);
        bytes32 pid = _submitTransfer(100e18);

        vm.prank(safe);
        proposalRegistry.approveProposal(pid);

        IProposalRegistry.Proposal memory p = proposalRegistry.getProposal(pid);
        assertEq(uint8(p.state), uint8(ProposalState.Approved));
        assertGt(p.earliestExecution, block.timestamp);
    }

    function test_ExecuteBeforeTimelock_Reverts() public {
        _depositUsdc(1_000_000e18);
        bytes32 pid = _submitTransfer(100e18);

        vm.prank(safe);
        proposalRegistry.approveProposal(pid);

        vm.expectRevert("TreasuryVault: timelock active");
        vault.executeApproved(pid);
    }

    function test_FullLifecycle_HappyPath() public {
        _depositUsdc(1_000_000e18);
        assertEq(usdc.balanceOf(address(vault)), 1_000_000e18);

        bytes32 pid = _submitTransfer(100e18);

        vm.prank(safe);
        proposalRegistry.approveProposal(pid);

        vm.warp(block.timestamp + 1 hours + 1);

        uint256 aliceBefore = usdc.balanceOf(alice);
        vault.executeApproved(pid);

        IProposalRegistry.Proposal memory p = proposalRegistry.getProposal(pid);
        assertEq(uint8(p.state), uint8(ProposalState.Executed));
        assertEq(usdc.balanceOf(alice), aliceBefore + 100e18, "alice should receive USDC");
        assertEq(usdc.balanceOf(address(vault)), 1_000_000e18 - 100e18, "vault balance reduced");
        assertTrue(vault.executedProposals(pid), "should be idempotency-locked");
    }

    function test_DoubleExecution_Reverts() public {
        _depositUsdc(1_000_000e18);
        bytes32 pid = _submitTransfer(100e18);

        vm.prank(safe);
        proposalRegistry.approveProposal(pid);
        vm.warp(block.timestamp + 1 hours + 1);
        vault.executeApproved(pid);

        vm.expectRevert("TreasuryVault: already executed");
        vault.executeApproved(pid);
    }

    function test_EmergencyPause_BlocksDeposit() public {
        vm.prank(guardian);
        vault.emergencyPause();
        assertTrue(vault.paused());

        usdc.mint(alice, 1000e18);
        vm.prank(alice);
        usdc.approve(address(vault), 1000e18);
        vm.expectRevert("TreasuryVault: paused");
        vm.prank(alice);
        vault.deposit(address(usdc), 1000e18);
    }

    function test_EmergencyUnpause_OnlySafe() public {
        vm.prank(guardian);
        vault.emergencyPause();
        vm.expectRevert("TreasuryVault: not safe");
        vm.prank(guardian);
        vault.emergencyUnpause();
        vm.prank(safe);
        vault.emergencyUnpause();
        assertFalse(vault.paused());
    }

    function test_CancelProposal_DuringTimelock() public {
        _depositUsdc(1_000_000e18);
        bytes32 pid = _submitTransfer(100e18);

        vm.prank(safe);
        proposalRegistry.approveProposal(pid);

        vm.prank(guardian);
        proposalRegistry.cancelProposal(pid, "Security review failed");

        IProposalRegistry.Proposal memory p = proposalRegistry.getProposal(pid);
        assertEq(uint8(p.state), uint8(ProposalState.Cancelled));
    }

    function test_CancelProposal_AfterTimelockExpired_Reverts() public {
        _depositUsdc(1_000_000e18);
        bytes32 pid = _submitTransfer(100e18);

        vm.prank(safe);
        proposalRegistry.approveProposal(pid);
        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert("ProposalRegistry: timelock already expired");
        vm.prank(guardian);
        proposalRegistry.cancelProposal(pid, "Too late");
    }

    function test_PolicyUpdate_7DayTimelock() public {
        bytes memory newPolicy = abi.encodePacked(hex"48454c58", uint32(2), alice);

        vm.prank(safe);
        bytes32 newHash = policyRegistry.proposeUpdate(newPolicy);

        vm.expectRevert("PolicyRegistry: timelock not expired");
        vm.prank(safe);
        policyRegistry.activateUpdate(newHash);

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(safe);
        policyRegistry.activateUpdate(newHash);
        assertEq(policyRegistry.activePolicyHash(), newHash);
    }

    function test_GetState_ReturnsRegisteredAssets() public {
        (ITreasuryVault.AssetEntry[] memory entries, uint256[] memory bals) = vault.getState();
        assertEq(entries.length, 1);
        assertEq(entries[0].token, address(usdc));
        assertEq(bals[0], 0);
    }

    function test_RegisterAsset_DuplicateReverts() public {
        vm.expectRevert("TreasuryVault: already registered");
        vm.prank(safe);
        vault.registerAsset(ITreasuryVault.AssetEntry({
            token: address(usdc),
            tokenType: 0,
            adapter: bytes32(0),
            active: true,
            registeredAt: 0
        }));
    }

    /// @notice Invariant: vault balance should never decrease outside of approved executions.
    /// @dev Documents the invariant that vault balances are non-decreasing absent proposals.
    function test_invariant_VaultBalanceNonDecreasing() public {
        // Deposit an initial amount
        uint256 initialAmount = 500_000e18;
        _depositUsdc(initialAmount);
        uint256 balanceBefore = usdc.balanceOf(address(vault));

        // Perform additional deposit — balance should only increase
        uint256 additionalDeposit = 100_000e18;
        _depositUsdc(additionalDeposit);
        uint256 balanceAfter = usdc.balanceOf(address(vault));

        assertGe(balanceAfter, balanceBefore, "invariant violated: vault balance decreased without execution");

        // Verify the exact expected balance
        assertEq(
            balanceAfter,
            initialAmount + additionalDeposit,
            "invariant violated: vault balance mismatch"
        );
    }

    function _depositUsdc(uint256 amount) internal {
        usdc.mint(alice, amount);
        vm.prank(alice);
        usdc.approve(address(vault), amount);
        vm.prank(alice);
        vault.deposit(address(usdc), amount);
    }

    function _makeTransferAction(uint256 amount) internal view returns (Action[] memory) {
        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            kind: ActionKind.TRANSFER,
            adapter: address(0),
            asset: address(usdc),
            amount: amount,
            params: abi.encode(alice)
        });
        return actions;
    }

    function _submitTransfer(uint256 amount) internal returns (bytes32) {
        Action[] memory actions = _makeTransferAction(amount);
        bytes32 ph = policyRegistry.activePolicyHash();
        vm.prank(agent);
        return proposalRegistry.submitProposal(ph, bytes32(0), actions, bytes32(0), bytes(""));
    }
}
