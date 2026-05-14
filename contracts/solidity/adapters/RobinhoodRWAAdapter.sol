// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IAdapter} from "../interfaces/IAdapter.sol";
import {ITaxEngine} from "../interfaces/ITaxEngine.sol";
import {Action, TreasuryState, ActionKind, TaxEventKind} from "../HelixTypes.sol";

/// @title RobinhoodRWAAdapter
/// @notice Trades tokenized equities (tSPY, tAAPL, ...) and tokenized ETFs/Treasuries on
///         Robinhood Chain. Also listens for corporate-action events (dividends, splits,
///         mergers, delistings) and forwards them to TaxEngine for tax-aware accounting.
/// @dev See docs/07-integrations.md §4. This is Helix's headline RWA integration.
contract RobinhoodRWAAdapter is IAdapter {
    bytes32 public constant override adapterId = keccak256("robinhood-rwa");

    address public immutable vault;
    address public immutable rwaExchange; // Robinhood Chain RWA exchange contract
    address public immutable taxEngine;
    address public guardian;
    bool public override circuitBreakerActive;

    /// @notice Listed status snapshot, updated by trusted corporate-action listener.
    mapping(address => bool) public isListed;

    event DividendReceived(address indexed asset, uint256 amount);
    event StockSplit(address indexed asset, uint256 oldBalance, uint256 newBalance, uint256 ratio);
    event MergerCompleted(address indexed oldAsset, address indexed newAsset, uint256 ratio);
    event AssetDelisted(address indexed asset);

    modifier onlyVault() {
        require(msg.sender == vault, "RWAAdapter: not vault");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "RWAAdapter: not guardian");
        _;
    }

    constructor(address _vault, address _rwaExchange, address _taxEngine, address _guardian) {
        vault = _vault;
        rwaExchange = _rwaExchange;
        taxEngine = _taxEngine;
        guardian = _guardian;
    }

    function supportedActions() external pure override returns (uint8[] memory kinds) {
        kinds = new uint8[](3);
        kinds[0] = uint8(ActionKind.BUY_RWA);
        kinds[1] = uint8(ActionKind.SELL_RWA);
        kinds[2] = uint8(ActionKind.REDEEM_RWA);
    }

    function execute(Action calldata a) external override onlyVault returns (bytes memory) {
        require(!circuitBreakerActive, "RWAAdapter: breaker");
        require(isListed[a.asset] || a.kind == ActionKind.SELL_RWA, "RWAAdapter: not listed");
        // TODO(mulerun): decode params; call rwaExchange.{buy,sell,redeem}
        revert("RWAAdapter: not implemented");
    }

    function simulate(Action calldata a, TreasuryState calldata pre)
        external
        view
        override
        returns (TreasuryState memory)
    {
        // TODO(mulerun): query rwaExchange view function for execution price
        revert("RWAAdapter: not implemented");
    }

    // ──────────── Corporate action callbacks ────────────
    /// @dev Called by trusted CorporateActionListener after observing on-chain events.
    function onDividend(address asset, uint256 amount) external {
        // TODO(mulerun): authorize sender (CorporateActionListener)
        // forward to TaxEngine; emit event
        ITaxEngine(taxEngine).recordCorporateAction(asset, TaxEventKind.DIVIDEND, amount, bytes32(0));
        emit DividendReceived(asset, amount);
    }

    function onSplit(address asset, uint256 oldBalance, uint256 newBalance, uint256 ratio) external {
        // TODO(mulerun): authorize; adjust cost basis in TaxEngine
        emit StockSplit(asset, oldBalance, newBalance, ratio);
    }

    function onMerger(address oldAsset, address newAsset, uint256 ratio) external {
        emit MergerCompleted(oldAsset, newAsset, ratio);
    }

    function onDelisting(address asset) external {
        // TODO(mulerun): triggers EMERGENCY_REDEEM proposal via off-chain agent
        isListed[asset] = false;
        emit AssetDelisted(asset);
    }

    function setListed(address asset, bool listed) external onlyGuardian {
        isListed[asset] = listed;
    }

    function tripBreaker() external onlyGuardian {
        circuitBreakerActive = true;
    }

    function resetBreaker() external onlyGuardian {
        circuitBreakerActive = false;
    }
}
