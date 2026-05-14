// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {ProposalRegistry} from "../../contracts/solidity/ProposalRegistry.sol";
import {Action, ActionKind} from "../../contracts/solidity/HelixTypes.sol";

contract DemoSubmitProposal is Script {
    function run() external {
        address proposalRegistry = vm.envOr(
            "PROPOSAL_REGISTRY",
            address(0x494960e21058290BB2F1328b6b837dCF26aA5DCb)
        );
        address recipient = vm.envOr(
            "DEMO_RECIPIENT",
            address(0x2F9fDE6B6FB8d7353aB80F082f85F0d70B809C3b)
        );
        address musdc = 0x9582d2dF303ec2B1fab104A77E249C05571fccC9;

        uint256 agentKey = vm.envUint("PRIVATE_KEY");
        address agent = vm.addr(agentKey);

        console2.log("=== Helix Demo: Submit Proposal ===");
        console2.log("Agent:", agent);
        console2.log("Recipient:", recipient);
        console2.log("Amount: 1000 mUSDC");

        ProposalRegistry reg = ProposalRegistry(proposalRegistry);
        uint256 bond = reg.agentBonds(agent);
        console2.log("Agent bond (ETH):", bond);

        vm.startBroadcast(agentKey);

        if (bond < 0.01 ether) {
            reg.postBond{value: 0.01 ether}();
            console2.log("Bond posted: 0.01 ETH");
        }

        Action[] memory actions = new Action[](1);
        actions[0] = Action({
            kind: ActionKind.TRANSFER,
            adapter: address(0),
            asset: musdc,
            amount: 1000 * 1e18,
            params: abi.encode(recipient)
        });

        bytes32 policyHash = bytes32(0);

        bytes32 proposalId = reg.submitProposal(
            policyHash,
            bytes32(block.number),
            actions,
            bytes32(0),
            bytes("")
        );

        vm.stopBroadcast();

        console2.log("=== Proposal Submitted ===");
        console2.logBytes32(proposalId);
    }
}
