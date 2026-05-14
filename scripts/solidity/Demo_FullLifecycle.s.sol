// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";
import {TreasuryVault} from "../../contracts/solidity/TreasuryVault.sol";
import {Action, ActionKind} from "../../contracts/solidity/HelixTypes.sol";

interface IERC20Simple {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract DemoFullLifecycle is Script {
    address constant VAULT = 0x2A46cF6493b377D45908254B0528e38990AA323f;
    address constant PROPOSAL_REG = 0x494960e21058290BB2F1328b6b837dCF26aA5DCb;
    address constant MUSDC = 0x9582d2dF303ec2B1fab104A77E249C05571fccC9;
    address constant SAFE = 0x2F9fDE6B6FB8d7353aB80F082f85F0d70B809C3b;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address recipient = vm.envOr("DEMO_RECIPIENT", deployer);

        TreasuryVault vault = TreasuryVault(payable(VAULT));
        ProposalRegistry reg = ProposalRegistry(PROPOSAL_REG);

        console2.log("=== Helix Full Lifecycle Demo ===");
        console2.log("Deployer/Agent:", deployer);
        console2.log("Recipient:", recipient);

        vm.startBroadcast(deployerKey);

        uint256 depositAmount = 10_000 * 1e18;
        IERC20Simple(MUSDC).approve(VAULT, depositAmount);
        vault.deposit(MUSDC, depositAmount);
        console2.log("Step 1: Deposited mUSDC");

        if (reg.agentBonds(deployer) < 0.01 ether) {
            reg.postBond{value: 0.01 ether}();
        }

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            kind: ActionKind.TRANSFER,
            adapter: address(0),
            asset: MUSDC,
            amount: 1000 * 1e18,
            params: abi.encode(recipient)
        });

        bytes32 proposalId = reg.submitProposal(
            bytes32(0), bytes32(block.number), actions, bytes32(0), bytes("")
        );
        console2.log("Step 2: Proposal submitted");
        console2.logBytes32(proposalId);

        vm.stopBroadcast();

        uint256 safeKey = vm.envOr("SAFE_KEY", deployerKey);
        vm.startBroadcast(safeKey);
        reg.approveProposal(proposalId);
        console2.log("Step 3: Proposal approved by Safe");
        vm.stopBroadcast();

        console2.log("Step 4: Wait 1 hour for timelock, then run Step 5.");
        console2.log("=== Demo complete (Steps 1-4). Run executeProposal manually after timelock. ===");
    }
}
