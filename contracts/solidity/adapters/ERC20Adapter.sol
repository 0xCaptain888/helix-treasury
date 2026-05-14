// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAdapter} from "../interfaces/IAdapter.sol";
import {Action, TreasuryState, ActionKind} from "../HelixTypes.sol";

/// @title ERC20Adapter
/// @notice Handles plain ERC20 TRANSFER and SWAP_UNISWAP_V3 actions.
contract ERC20Adapter is IAdapter {
    bytes32 public constant override adapterId = keccak256("erc20-uniswap-v3");

    address public immutable vault;
    address public immutable uniswapRouter;
    uint32 public constant MAX_SLIPPAGE_BPS = 100; // 1% global ceiling

    bool public override circuitBreakerActive;
    address public guardian;

    modifier onlyVault() {
        require(msg.sender == vault, "ERC20Adapter: not vault");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "ERC20Adapter: not guardian");
        _;
    }

    constructor(address _vault, address _uniswapRouter, address _guardian) {
        vault = _vault;
        uniswapRouter = _uniswapRouter;
        guardian = _guardian;
    }

    function supportedActions() external pure override returns (uint8[] memory kinds) {
        kinds = new uint8[](2);
        kinds[0] = uint8(ActionKind.TRANSFER);
        kinds[1] = uint8(ActionKind.SWAP);
    }

    function execute(Action calldata a) external override onlyVault returns (bytes memory) {
        require(!circuitBreakerActive, "ERC20Adapter: breaker");
        if (a.kind == ActionKind.TRANSFER) {
            // TODO(mulerun): decode params for destination; safeTransfer
        } else if (a.kind == ActionKind.SWAP) {
            // TODO(mulerun): decode (tokenOut, minOut, fee, path), enforce MAX_SLIPPAGE_BPS, call router
        } else {
            revert("ERC20Adapter: unsupported");
        }
        revert("ERC20Adapter: not implemented");
    }

    function simulate(Action calldata a, TreasuryState calldata pre)
        external
        view
        override
        returns (TreasuryState memory)
    {
        // TODO(mulerun): use quoter to project post-state
        revert("ERC20Adapter: not implemented");
    }

    function tripBreaker() external onlyGuardian {
        circuitBreakerActive = true;
    }

    function resetBreaker() external onlyGuardian {
        circuitBreakerActive = false;
    }
}
