// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAdapter} from "../interfaces/IAdapter.sol";
import {Action, TreasuryState, ActionKind} from "../HelixTypes.sol";

/// @title AaveAdapter
/// @notice Handles SUPPLY / WITHDRAW / BORROW / REPAY against Aave V3.
/// @dev See docs/07-integrations.md §2.
contract AaveAdapter is IAdapter {
    bytes32 public constant override adapterId = keccak256("aave-v3-arbitrum");

    address public immutable vault;
    address public immutable aavePool; // IPool
    address public guardian;

    bool public override circuitBreakerActive;
    uint256 public lastReserveRate; // for anomaly detection

    modifier onlyVault() {
        require(msg.sender == vault, "AaveAdapter: not vault");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "AaveAdapter: not guardian");
        _;
    }

    constructor(address _vault, address _aavePool, address _guardian) {
        vault = _vault;
        aavePool = _aavePool;
        guardian = _guardian;
    }

    function supportedActions() external pure override returns (uint8[] memory kinds) {
        kinds = new uint8[](4);
        kinds[0] = uint8(ActionKind.SUPPLY);
        kinds[1] = uint8(ActionKind.WITHDRAW);
        kinds[2] = uint8(ActionKind.BORROW);
        kinds[3] = uint8(ActionKind.REPAY);
    }

    function execute(Action calldata a) external override onlyVault returns (bytes memory) {
        require(!circuitBreakerActive, "AaveAdapter: breaker");

        if (a.kind == ActionKind.SUPPLY) {
            // Approve aavePool to spend the asset
            (bool approveOk,) = a.asset.call(
                abi.encodeWithSignature("approve(address,uint256)", aavePool, a.amount)
            );
            require(approveOk, "AaveAdapter: approve failed");

            (bool ok, bytes memory result) = aavePool.call(
                abi.encodeWithSignature("supply(address,uint256,address,uint16)", a.asset, a.amount, vault, 0)
            );
            require(ok, "AaveAdapter: supply failed");
            return result;
        } else if (a.kind == ActionKind.WITHDRAW) {
            (bool ok, bytes memory result) = aavePool.call(
                abi.encodeWithSignature("withdraw(address,uint256,address)", a.asset, a.amount, vault)
            );
            require(ok, "AaveAdapter: withdraw failed");
            return result;
        } else if (a.kind == ActionKind.BORROW) {
            (bool ok, bytes memory result) = aavePool.call(
                abi.encodeWithSignature(
                    "borrow(address,uint256,uint256,uint16,address)", a.asset, a.amount, 2, 0, vault
                )
            );
            require(ok, "AaveAdapter: borrow failed");
            return result;
        } else if (a.kind == ActionKind.REPAY) {
            // Approve aavePool to spend the asset
            (bool approveOk,) = a.asset.call(
                abi.encodeWithSignature("approve(address,uint256)", aavePool, a.amount)
            );
            require(approveOk, "AaveAdapter: approve failed");

            (bool ok, bytes memory result) = aavePool.call(
                abi.encodeWithSignature("repay(address,uint256,uint256,address)", a.asset, a.amount, 2, vault)
            );
            require(ok, "AaveAdapter: repay failed");
            return result;
        } else {
            revert("AaveAdapter: unsupported");
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
