// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ITreasuryVault} from "./interfaces/ITreasuryVault.sol";
import {IProposalRegistry} from "./interfaces/IProposalRegistry.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {ITaxEngine} from "./interfaces/ITaxEngine.sol";
import {IOracleAggregator} from "./interfaces/IOracleAggregator.sol";
import {Action, TreasuryState, MarketState, Verdict, VerdictKind, ActionKind, ProposalState} from "./HelixTypes.sol";

/// @title TreasuryVault
/// @notice Single custody point for treasury assets. Dispatches adapter calls only after a
///         proposal has cleared PolicyEngine + Safe approval + timelock + execution-time
///         re-evaluation. NON-upgradable.
/// @dev See docs/04-contracts.md §4 and docs/05-security-model.md §3.
contract TreasuryVault is ITreasuryVault {
    // ──────────── Storage ────────────
    mapping(address => AssetEntry) public assetsMap;
    address[] public assetList;

    address public override safe;
    address public override guardian;
    address public proposalRegistry;
    address public engine;
    address public taxEngine;
    address public oracleAggregator;

    bool public override paused;
    uint256 public lastActionAt;
    uint256 public totalMovement24h; // sliding window in USDC-6
    mapping(uint256 => uint256) private movementByHour; // ring buffer (hour → moved)

    mapping(bytes32 => bool) public executedProposals; // idempotency

    // Re-entrancy guard
    uint256 private _locked = 1;
    modifier nonReentrant() {
        require(_locked == 1, "TreasuryVault: reentrancy");
        _locked = 2;
        _;
        _locked = 1;
    }

    modifier onlySafe() {
        require(msg.sender == safe, "TreasuryVault: not safe");
        _;
    }

    modifier onlyGuardian() {
        require(msg.sender == guardian, "TreasuryVault: not guardian");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "TreasuryVault: paused");
        _;
    }

    // ──────────── Constructor ────────────
    constructor(
        address _safe,
        address _guardian,
        address _proposalRegistry,
        address _engine,
        address _taxEngine,
        address _oracleAggregator
    ) {
        require(_safe != address(0) && _engine != address(0), "TreasuryVault: zero addr");
        safe = _safe;
        guardian = _guardian;
        proposalRegistry = _proposalRegistry;
        engine = _engine;
        taxEngine = _taxEngine;
        oracleAggregator = _oracleAggregator;
    }

    // ──────────── Asset registration ────────────
    function registerAsset(AssetEntry calldata entry) external override onlySafe {
        require(entry.token != address(0), "TreasuryVault: zero token");
        require(!assetsMap[entry.token].active, "TreasuryVault: already registered");

        assetsMap[entry.token] = entry;
        assetList.push(entry.token);
        emit AssetRegistered(entry.token, bytes32(bytes20(entry.adapter)));
    }

    function deregisterAsset(address token) external override onlySafe {
        require(assetsMap[token].active, "TreasuryVault: not registered");
        assetsMap[token].active = false;
        emit AssetDeregistered(token);
    }

    // ──────────── State views ────────────
    function getState() external view override returns (AssetEntry[] memory entries, uint256[] memory balances) {
        uint256 len = assetList.length;
        entries = new AssetEntry[](len);
        balances = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            address token = assetList[i];
            entries[i] = assetsMap[token];
            // Read ERC20 balance
            (, bytes memory data) = token.staticcall(
                abi.encodeWithSignature("balanceOf(address)", address(this))
            );
            if (data.length >= 32) {
                balances[i] = abi.decode(data, (uint256));
            }
        }
    }

    function getNAV() external view override returns (uint256 totalNAVUsdc) {
        IOracleAggregator oracle = IOracleAggregator(oracleAggregator);
        for (uint256 i = 0; i < assetList.length; i++) {
            address token = assetList[i];
            if (!assetsMap[token].active) continue;

            // Read balance
            (, bytes memory data) = token.staticcall(
                abi.encodeWithSignature("balanceOf(address)", address(this))
            );
            if (data.length < 32) continue;
            uint256 balance = abi.decode(data, (uint256));
            if (balance == 0) continue;

            // Get price from oracle
            IOracleAggregator.PriceQuote memory quote = oracle.priceOf(token);
            // Normalize: balance * priceUsd6 / 10^decimals
            uint8 decimals = assetsMap[token].decimals;
            totalNAVUsdc += (balance * quote.priceUsd6) / (10 ** decimals);
        }
    }

    // ──────────── Deposits ────────────
    function deposit(address token, uint256 amount) external override whenNotPaused {
        require(assetsMap[token].active, "TreasuryVault: asset not registered");
        require(amount > 0, "TreasuryVault: zero amount");

        // Pull tokens via transferFrom
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TreasuryVault: transfer failed");

        emit Deposited(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount, address to) external override onlySafe {
        require(to != address(0), "TreasuryVault: zero recipient");

        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TreasuryVault: transfer failed");
    }

    // ──────────── Execution ────────────
    /// @dev This function is the heart of the safety model. See docs/04-contracts.md §4 for the
    ///      full flow. Reverts on stale state, expired proposals, hard-constraint violations.
    function executeApproved(bytes32 proposalId) external override nonReentrant whenNotPaused {
        require(!executedProposals[proposalId], "TreasuryVault: already executed");

        IProposalRegistry reg = IProposalRegistry(proposalRegistry);
        IProposalRegistry.Proposal memory p = reg.getProposal(proposalId);

        // Validate proposal state
        require(p.state == ProposalState.Approved, "TreasuryVault: not approved");
        require(block.timestamp >= p.earliestExecution, "TreasuryVault: timelock active");
        require(block.timestamp <= p.expiresAt, "TreasuryVault: proposal expired");

        // Re-evaluate PolicyEngine at execution time (defense-in-depth)
        TreasuryState memory liveState = _liveStateForEngine();
        MarketState memory liveMarket = _liveMarketForEngine();
        Verdict memory v = IPolicyEngine(engine).evaluate(p.policyHash, liveState, liveMarket, p.actions);
        require(v.kind == VerdictKind.Approve, "TreasuryVault: stale verdict");

        // Dispatch each action to its adapter
        for (uint256 i = 0; i < p.actions.length; i++) {
            _dispatch(p.actions[i]);
            emit ActionDispatched(uint8(p.actions[i].kind), p.actions[i].adapter, p.actions[i].params);
        }

        // Record tax events
        ITaxEngine(taxEngine).recordExecution(proposalId, p.actions);

        // Mark as executed
        executedProposals[proposalId] = true;
        bytes32 postStateHash = keccak256(abi.encode(_liveStateForEngine()));
        reg.markExecuted(proposalId, postStateHash);

        lastActionAt = block.timestamp;
        emit Executed(proposalId);
    }

    function _dispatch(Action memory a) internal {
        require(a.kind != ActionKind.NOOP, "TreasuryVault: noop");
        IAdapter adapter = IAdapter(a.adapter);
        require(!adapter.circuitBreakerActive(), "TreasuryVault: adapter breaker");
        adapter.execute(a);

        // Update 24h movement tracking
        uint256 hour = block.timestamp / 1 hours;
        movementByHour[hour % 24] += a.amount;
    }

    // ──────────── Internal state builders ────────────

    function _liveStateForEngine() internal view returns (TreasuryState memory) {
        uint256 len = assetList.length;
        address[] memory assets = new address[](len);
        uint256[] memory balances = new uint256[](len);

        for (uint256 i = 0; i < len; i++) {
            assets[i] = assetList[i];
            (, bytes memory data) = assets[i].staticcall(
                abi.encodeWithSignature("balanceOf(address)", address(this))
            );
            if (data.length >= 32) {
                balances[i] = abi.decode(data, (uint256));
            }
        }

        uint256 nav = this.getNAV();

        return TreasuryState({
            assets: assets,
            balances: balances,
            totalNAVUsdc: nav,
            snapshotAt: uint64(block.timestamp),
            stateHash: keccak256(abi.encode(assets, balances, nav, block.timestamp))
        });
    }

    function _liveMarketForEngine() internal view returns (MarketState memory) {
        IOracleAggregator oracle = IOracleAggregator(oracleAggregator);
        uint256 len = assetList.length;
        address[] memory assets = new address[](len);
        uint256[] memory prices = new uint256[](len);
        uint64[] memory observed = new uint64[](len);

        for (uint256 i = 0; i < len; i++) {
            assets[i] = assetList[i];
            if (assetsMap[assets[i]].active) {
                IOracleAggregator.PriceQuote memory q = oracle.priceOf(assets[i]);
                prices[i] = q.priceUsd6;
                observed[i] = q.observedAt;
            }
        }

        return MarketState({
            assets: assets,
            pricesUsd6: prices,
            observedAt: observed,
            marketHash: keccak256(abi.encode(assets, prices, observed))
        });
    }

    // ──────────── Emergency ────────────
    function emergencyPause() external override onlyGuardian {
        paused = true;
        emit EmergencyPaused(msg.sender);
    }

    function emergencyUnpause() external override onlySafe {
        paused = false;
        emit EmergencyUnpaused(msg.sender);
    }
}
