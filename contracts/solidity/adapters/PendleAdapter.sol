// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAdapter} from "../interfaces/IAdapter.sol";
import {Action, TreasuryState, ActionKind} from "../HelixTypes.sol";

/// @title PendleAdapter
/// @notice Handles BUY_PT / SELL_PT / BUY_YT / SELL_YT / REDEEM_PT_AT_MATURITY for Pendle
///         markets on Arbitrum.
/// @dev See docs/07-integrations.md §3.
contract PendleAdapter is IAdapter {
    bytes32 public constant override adapterId = keccak256("pendle-arbitrum");

    address public immutable vault;
    address public immutable pendleRouter;
    address public guardian;
    bool public override circuitBreakerActive;

    /// @notice Per-market maturity tracking for auto-redeem proposals.
    mapping(address => uint64) public maturityOf;

    event PTMaturityApproaching(address indexed ptToken, uint64 maturity);

    modifier onlyVault() {
        require(msg.sender == vault, "PendleAdapter: not vault");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "PendleAdapter: not guardian");
        _;
    }

    constructor(address _vault, address _pendleRouter, address _guardian) {
        vault = _vault;
        pendleRouter = _pendleRouter;
        guardian = _guardian;
    }

    function supportedActions() external pure override returns (uint8[] memory kinds) {
        kinds = new uint8[](5);
        kinds[0] = uint8(ActionKind.BUY_PT);
        kinds[1] = uint8(ActionKind.SELL_PT);
        kinds[2] = uint8(ActionKind.BUY_YT);
        kinds[3] = uint8(ActionKind.SELL_YT);
        kinds[4] = uint8(ActionKind.REDEEM_PT_AT_MATURITY);
    }

    function execute(Action calldata a) external override onlyVault returns (bytes memory) {
        require(!circuitBreakerActive, "PendleAdapter: breaker");

        if (a.kind == ActionKind.BUY_PT) {
            return _buyPT(a);
        } else if (a.kind == ActionKind.SELL_PT) {
            return _sellPT(a);
        } else if (a.kind == ActionKind.BUY_YT) {
            return _buyYT(a);
        } else if (a.kind == ActionKind.SELL_YT) {
            return _sellYT(a);
        } else if (a.kind == ActionKind.REDEEM_PT_AT_MATURITY) {
            return _redeemPT(a);
        } else {
            revert("PendleAdapter: unsupported action");
        }
    }

    function simulate(Action calldata a, TreasuryState calldata pre)
        external
        view
        override
        returns (TreasuryState memory post)
    {
        post = pre;
        // Simulate by querying PendleRouter view functions for swap preview
        // In production: call pendleRouter.viewSwap to project post-state
        // For now: return pre-state (actual simulation requires router integration)
    }

    /// @notice Register a PT token's maturity date for auto-redeem tracking.
    function registerMaturity(address ptToken, uint64 maturity) external onlyGuardian {
        maturityOf[ptToken] = maturity;
    }

    /// @notice Check if a PT token is approaching maturity (within 7 days).
    function checkMaturity(address ptToken) external view returns (bool approaching) {
        uint64 mat = maturityOf[ptToken];
        if (mat == 0) return false;
        approaching = block.timestamp >= mat - 7 days && block.timestamp < mat;
    }

    function tripBreaker() external onlyGuardian {
        circuitBreakerActive = true;
    }

    function resetBreaker() external onlyGuardian {
        circuitBreakerActive = false;
    }

    // ──────────── Internal execution ────────────

    function _buyPT(Action calldata a) internal returns (bytes memory) {
        // Decode params: (address market, address ptToken, uint256 minPtOut)
        (address market, address ptToken, uint256 minPtOut) = abi.decode(a.params, (address, address, uint256));
        // Approve underlying to pendleRouter
        _approve(a.asset, pendleRouter, a.amount);
        // Call pendleRouter.swapExactTokenForPt(receiver, market, minPtOut, ...)
        (bool success, bytes memory result) = pendleRouter.call(
            abi.encodeWithSignature(
                "swapExactTokenForPt(address,address,uint256,uint256,bytes)",
                address(this), market, minPtOut, a.amount, ""
            )
        );
        require(success, "PendleAdapter: buyPT failed");
        // Track maturity
        if (maturityOf[ptToken] == 0) {
            // Query maturity from market
            (, bytes memory matData) = market.staticcall(abi.encodeWithSignature("expiry()"));
            if (matData.length >= 32) {
                maturityOf[ptToken] = uint64(abi.decode(matData, (uint256)));
            }
        }
        return result;
    }

    function _sellPT(Action calldata a) internal returns (bytes memory) {
        (address market,, uint256 minTokenOut) = abi.decode(a.params, (address, address, uint256));
        _approve(a.asset, pendleRouter, a.amount);
        (bool success, bytes memory result) = pendleRouter.call(
            abi.encodeWithSignature(
                "swapExactPtForToken(address,address,uint256,uint256,bytes)",
                address(this), market, a.amount, minTokenOut, ""
            )
        );
        require(success, "PendleAdapter: sellPT failed");
        return result;
    }

    function _buyYT(Action calldata a) internal returns (bytes memory) {
        (address market,, uint256 minYtOut) = abi.decode(a.params, (address, address, uint256));
        _approve(a.asset, pendleRouter, a.amount);
        (bool success, bytes memory result) = pendleRouter.call(
            abi.encodeWithSignature(
                "swapExactTokenForYt(address,address,uint256,uint256,bytes)",
                address(this), market, minYtOut, a.amount, ""
            )
        );
        require(success, "PendleAdapter: buyYT failed");
        return result;
    }

    function _sellYT(Action calldata a) internal returns (bytes memory) {
        (address market,, uint256 minTokenOut) = abi.decode(a.params, (address, address, uint256));
        _approve(a.asset, pendleRouter, a.amount);
        (bool success, bytes memory result) = pendleRouter.call(
            abi.encodeWithSignature(
                "swapExactYtForToken(address,address,uint256,uint256,bytes)",
                address(this), market, a.amount, minTokenOut, ""
            )
        );
        require(success, "PendleAdapter: sellYT failed");
        return result;
    }

    function _redeemPT(Action calldata a) internal returns (bytes memory) {
        (address market, address ptToken,) = abi.decode(a.params, (address, address, uint256));
        uint64 mat = maturityOf[ptToken];
        require(mat > 0 && block.timestamp >= mat, "PendleAdapter: not matured");
        _approve(ptToken, pendleRouter, a.amount);
        (bool success, bytes memory result) = pendleRouter.call(
            abi.encodeWithSignature(
                "redeemDueInterestAndRewards(address,address,address)",
                address(this), market, ptToken
            )
        );
        require(success, "PendleAdapter: redeem failed");
        return result;
    }

    function _approve(address token, address spender, uint256 amount) internal {
        (bool success,) = token.call(
            abi.encodeWithSignature("approve(address,uint256)", spender, amount)
        );
        require(success, "PendleAdapter: approve failed");
    }
}
