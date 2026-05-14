// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ITreasuryVault} from "./interfaces/ITreasuryVault.sol";
import {IProposalRegistry} from "./interfaces/IProposalRegistry.sol";
import {IPolicyEngine} from "./interfaces/IPolicyEngine.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {ITaxEngine} from "./interfaces/ITaxEngine.sol";
import {IOracleAggregator} from "./interfaces/IOracleAggregator.sol";
import {Action, TreasuryState, MarketState, Verdict, VerdictKind, ActionKind, ProposalState} from "./HelixTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TreasuryVault is ITreasuryVault {
    using SafeERC20 for IERC20;

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

    mapping(uint256 => uint256) private _movementByHour;
    uint256 private _lastMovementHour;

    mapping(bytes32 => bool) public executedProposals;

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
        require(msg.sender == guardian || msg.sender == safe, "TreasuryVault: not guardian");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "TreasuryVault: paused");
        _;
    }

    constructor(
        address _safe,
        address _guardian,
        address _proposalRegistry,
        address _engine,
        address _taxEngine,
        address _oracleAggregator
    ) {
        require(_safe != address(0), "TreasuryVault: zero safe");
        require(_engine != address(0), "TreasuryVault: zero engine");
        safe = _safe;
        guardian = _guardian;
        proposalRegistry = _proposalRegistry;
        engine = _engine;
        taxEngine = _taxEngine;
        oracleAggregator = _oracleAggregator;
    }

    function registerAsset(AssetEntry calldata entry) external override onlySafe {
        require(entry.token != address(0), "TreasuryVault: zero token");
        require(!assetsMap[entry.token].active, "TreasuryVault: already registered");
        assetsMap[entry.token] = AssetEntry({
            token: entry.token,
            tokenType: entry.tokenType,
            adapter: entry.adapter,
            active: true,
            registeredAt: uint64(block.timestamp)
        });
        assetList.push(entry.token);
        emit AssetRegistered(entry.token);
    }

    function deregisterAsset(address token) external override onlySafe {
        require(assetsMap[token].active, "TreasuryVault: not registered");
        require(
            IERC20(token).balanceOf(address(this)) == 0,
            "TreasuryVault: non-zero balance"
        );
        assetsMap[token].active = false;
        for (uint256 i = 0; i < assetList.length; i++) {
            if (assetList[i] == token) {
                assetList[i] = assetList[assetList.length - 1];
                assetList.pop();
                break;
            }
        }
        emit AssetDeregistered(token);
    }

    function getState()
        external
        view
        override
        returns (AssetEntry[] memory entries, uint256[] memory balances)
    {
        uint256 n = assetList.length;
        entries = new AssetEntry[](n);
        balances = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            address token = assetList[i];
            entries[i] = assetsMap[token];
            balances[i] = IERC20(token).balanceOf(address(this));
        }
    }

    function getNAV() external view override returns (uint256 totalNAVUsdc) {
        if (oracleAggregator == address(0)) return 0;
        uint256 n = assetList.length;
        for (uint256 i = 0; i < n; i++) {
            address token = assetList[i];
            if (!assetsMap[token].active) continue;
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) continue;
            try IOracleAggregator(oracleAggregator).getPrice(token) returns (
                uint256 priceUsdc6,
                uint256
            ) {
                totalNAVUsdc += (balance * priceUsdc6) / 1e12;
            } catch {}
        }
    }

    function _buildTreasuryState() internal view returns (TreasuryState memory state) {
        uint256 n = assetList.length;
        address[] memory assets = new address[](n);
        uint256[] memory balances = new uint256[](n);
        uint256[] memory prices = new uint256[](n);
        uint256 nav = 0;
        for (uint256 i = 0; i < n; i++) {
            address token = assetList[i];
            assets[i] = token;
            balances[i] = IERC20(token).balanceOf(address(this));
            if (oracleAggregator != address(0)) {
                try IOracleAggregator(oracleAggregator).getPrice(token) returns (
                    uint256 p, uint256
                ) {
                    prices[i] = p;
                    nav += (balances[i] * p) / 1e12;
                } catch {}
            }
        }
        bytes32 stateHash = keccak256(abi.encode(assets, balances, block.timestamp));
        state = TreasuryState({
            assets: assets,
            balances: balances,
            totalNAVUsdc: nav,
            snapshotAt: uint64(block.timestamp),
            stateHash: stateHash
        });
    }

    function deposit(address token, uint256 amount) external override whenNotPaused {
        require(assetsMap[token].active, "TreasuryVault: asset not registered");
        require(amount > 0, "TreasuryVault: zero amount");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount, address to)
        external
        override
        onlySafe
        nonReentrant
    {
        require(to != address(0), "TreasuryVault: zero recipient");
        require(amount > 0, "TreasuryVault: zero amount");
        IERC20(token).safeTransfer(to, amount);
        emit Withdrawn(token, amount, to);
    }

    function executeApproved(bytes32 proposalId)
        external
        override
        nonReentrant
        whenNotPaused
    {
        require(!executedProposals[proposalId], "TreasuryVault: already executed");

        IProposalRegistry reg = IProposalRegistry(proposalRegistry);
        IProposalRegistry.Proposal memory p = reg.getProposal(proposalId);

        require(
            p.state == ProposalState.Approved,
            "TreasuryVault: proposal not approved"
        );
        require(
            block.timestamp >= p.earliestExecution,
            "TreasuryVault: timelock active"
        );
        require(
            block.timestamp <= p.submittedAt + reg.PROPOSAL_TTL(),
            "TreasuryVault: proposal expired"
        );

        TreasuryState memory liveState = _buildTreasuryState();
        bytes memory stateBytes = abi.encode(
            uint256(liveState.assets.length),
            uint256(0),
            liveState.totalNAVUsdc,
            uint256(liveState.snapshotAt),
            liveState.stateHash,
            liveState.assets,
            liveState.balances,
            liveState.balances
        );

        bytes memory actionsBytes = _encodeActions(p.actions);

        bytes memory verdictBytes = IPolicyEngine(engine).evaluate(
            p.policyHash,
            stateBytes,
            bytes(""),
            actionsBytes
        );

        Verdict memory verdict = _decodeVerdict(verdictBytes);
        require(
            verdict.kind == VerdictKind.Approve,
            "TreasuryVault: stale verdict -- policy rejected at execution"
        );

        for (uint256 i = 0; i < p.actions.length; i++) {
            _dispatch(p.actions[i]);
        }

        if (taxEngine != address(0)) {
            try ITaxEngine(taxEngine).recordExecution(proposalId, p.actions) {}
            catch {}
        }

        executedProposals[proposalId] = true;
        lastActionAt = block.timestamp;

        bytes32 postStateHash = keccak256(abi.encode(liveState.assets, liveState.balances, block.timestamp));
        reg.markExecuted(proposalId, postStateHash);

        emit ProposalExecuted(proposalId);
    }

    function _dispatch(Action memory a) internal {
        if (a.kind == ActionKind.NOOP) return;
        if (a.adapter != address(0)) {
            IAdapter adapter = IAdapter(a.adapter);
            require(!adapter.circuitBreakerActive(), "TreasuryVault: adapter circuit breaker");
            if (a.asset != address(0) && a.amount > 0) {
                IERC20(a.asset).safeIncreaseAllowance(a.adapter, a.amount);
            }
            adapter.execute(a);
            if (a.asset != address(0)) {
                uint256 remaining = IERC20(a.asset).allowance(address(this), a.adapter);
                if (remaining > 0) {
                    IERC20(a.asset).safeDecreaseAllowance(a.adapter, remaining);
                }
            }
        } else if (a.kind == ActionKind.TRANSFER) {
            address recipient = abi.decode(a.params, (address));
            require(assetsMap[a.asset].active, "TreasuryVault: unregistered asset");
            IERC20(a.asset).safeTransfer(recipient, a.amount);
        }
    }

    function emergencyPause() external override onlyGuardian {
        paused = true;
        emit EmergencyPaused(msg.sender);
    }

    function emergencyUnpause() external override onlySafe {
        paused = false;
        emit EmergencyUnpaused(msg.sender);
    }

    function _encodeActions(Action[] memory actions) internal pure returns (bytes memory) {
        bytes memory out = abi.encode(uint256(actions.length));
        for (uint256 i = 0; i < actions.length; i++) {
            Action memory a = actions[i];
            out = bytes.concat(
                out,
                abi.encode(uint256(uint8(a.kind))),
                abi.encode(a.adapter),
                abi.encode(a.asset),
                abi.encode(a.amount),
                abi.encode(uint256(a.params.length)),
                a.params,
                new bytes((32 - a.params.length % 32) % 32)
            );
        }
        return out;
    }

    function _decodeVerdict(bytes memory data) internal pure returns (Verdict memory v) {
        require(data.length >= 6 * 32, "TreasuryVault: verdict too short");
        uint256 kind;
        bytes32 policyHash;
        bytes32 computedActionsHash;
        bytes32 marketStateHash;
        uint64 evaluatedAt;
        assembly {
            kind              := mload(add(data, 32))
            policyHash        := mload(add(data, 64))
            computedActionsHash := mload(add(data, 96))
            marketStateHash   := mload(add(data, 128))
            evaluatedAt       := mload(add(data, 160))
        }
        uint256 reasonLen;
        assembly { reasonLen := mload(add(data, 192)) }
        bytes memory reason = new bytes(reasonLen);
        for (uint256 i = 0; i < reasonLen && 224 + i < data.length; i++) {
            reason[i] = data[224 + i];
        }
        v = Verdict({
            kind: VerdictKind(kind),
            policyHash: policyHash,
            computedActionsHash: computedActionsHash,
            marketStateHash: marketStateHash,
            evaluatedAt: evaluatedAt,
            rejectReason: reason
        });
    }
}
