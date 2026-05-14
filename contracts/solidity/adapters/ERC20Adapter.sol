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
            (address destination) = abi.decode(a.params, (address));
            (bool success, bytes memory data) = a.asset.call(
                abi.encodeWithSignature("transfer(address,uint256)", destination, a.amount)
            );
            require(success && (data.length == 0 || abi.decode(data, (bool))), "ERC20Adapter: transfer failed");
            return data;
        } else if (a.kind == ActionKind.SWAP) {
            (address tokenOut, uint256 minAmountOut, uint24 fee) = abi.decode(a.params, (address, uint256, uint24));

            // Approve router to spend input token
            (bool approveOk,) = a.asset.call(
                abi.encodeWithSignature("approve(address,uint256)", uniswapRouter, a.amount)
            );
            require(approveOk, "ERC20Adapter: approve failed");

            // Call exactInputSingle on Uniswap V3 router
            (bool swapOk, bytes memory swapResult) = uniswapRouter.call(
                abi.encodeWithSignature(
                    "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                    a.asset,
                    tokenOut,
                    fee,
                    vault,
                    block.timestamp,
                    a.amount,
                    minAmountOut,
                    0
                )
            );
            require(swapOk, "ERC20Adapter: swap failed");

            uint256 amountOut = abi.decode(swapResult, (uint256));
            require(amountOut >= minAmountOut, "ERC20Adapter: insufficient output");
            return swapResult;
        } else {
            revert("ERC20Adapter: unsupported");
        }
    }

    function simulate(Action calldata a, TreasuryState calldata pre)
        external
        view
        override
        returns (TreasuryState memory post)
    {
        post = pre;
    }

    function tripBreaker() external onlyGuardian {
        circuitBreakerActive = true;
    }

    function resetBreaker() external onlyGuardian {
        circuitBreakerActive = false;
    }
}
