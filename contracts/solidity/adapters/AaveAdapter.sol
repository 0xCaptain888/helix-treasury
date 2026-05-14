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
        // TODO(mulerun): check reserve rate anomaly; trip breaker on > 10% rate jump
        // TODO(mulerun): dispatch based on a.kind
        revert("AaveAdapter: not implemented");
    }

    function simulate(Action calldata a, TreasuryState calldata pre)
        external
        view
        override
        returns (TreasuryState memory)
    {
        // TODO(mulerun): call Pool.getReserveData; project aToken balance change
        revert("AaveAdapter: not implemented");
    }

    function tripBreaker() external onlyGuardian {
        circuitBreakerActive = true;
    }

    function resetBreaker() external onlyGuardian {
        circuitBreakerActive = false;
    }
}
