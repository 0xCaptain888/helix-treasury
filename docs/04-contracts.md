# 04 — Contracts

> Complete contract interfaces, storage layouts, and events for all Helix on-chain components.

## Contract Map

```
┌────────────────────────────────────────────────────────────────────┐
│                       HELIX CONTRACT GRAPH                         │
│                                                                    │
│   ┌───────────────────────┐                                       │
│   │   PolicyRegistry      │     stores policy bytecode + meta     │
│   │   (Solidity)          │     owner: Safe                       │
│   └──────────┬────────────┘                                       │
│              │ (read)                                              │
│              ▼                                                     │
│   ┌───────────────────────┐                                       │
│   │   PolicyEngine        │     pure evaluator                    │
│   │   (Stylus / Rust)     │     no state of its own               │
│   └──────────┬────────────┘                                       │
│              │ (called by)                                         │
│              ▼                                                     │
│   ┌───────────────────────┐                                       │
│   │   ProposalRegistry    │     stores proposals + timelock       │
│   │   (Solidity)          │                                       │
│   └──────────┬────────────┘                                       │
│              │ (authorizes)                                        │
│              ▼                                                     │
│   ┌───────────────────────┐     custodies funds                   │
│   │   TreasuryVault       │     dispatches to adapters            │
│   │   (Solidity)          │     owner: Safe                       │
│   └──────────┬────────────┘                                       │
│              │ (calls)                                             │
│      ┌───────┼───────┬─────────────────────┐                       │
│      ▼       ▼       ▼                     ▼                       │
│ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────────┐               │
│ │  Aave   │ │ Pendle  │ │  RWA    │ │   ERC20     │               │
│ │ Adapter │ │ Adapter │ │ Adapter │ │   Adapter   │               │
│ └─────────┘ └─────────┘ └─────────┘ └─────────────┘               │
│                                                                    │
│   ┌───────────────────────┐                                       │
│   │   TaxEngine           │     hooked from TreasuryVault         │
│   │   (Solidity)          │     produces tax events               │
│   └───────────────────────┘                                       │
│                                                                    │
│   ┌───────────────────────┐                                       │
│   │   OracleAggregator    │     wraps Chainlink + Pyth            │
│   │   (Solidity)          │     freshness + deviation guard       │
│   └───────────────────────┘                                       │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

## 1. PolicyEngine (Stylus / Rust)

The PolicyEngine is the deterministic verdict-producing component. It is **stateless** — it reads from `PolicyRegistry`, `TreasuryVault`, and `OracleAggregator`, and produces a verdict.

### Public ABI

```rust
// Stylus pseudo-interface (presented as Solidity for clarity)

interface IPolicyEngine {
    enum VerdictKind { Approve, Reject, Stale }

    struct Verdict {
        VerdictKind kind;
        bytes32 policyHash;
        bytes32 computedActionsHash;
        bytes32 marketStateHash;
        uint64  evaluatedAt;
        bytes   rejectReason;   // empty if Approve
    }

    function evaluate(
        bytes32 policyHash,
        bytes32 treasuryStateHash,
        bytes32 marketStateHash,
        Action[] calldata proposedActions
    ) external view returns (Verdict memory);

    function checkHardConstraints(
        bytes32 policyHash,
        TreasuryState calldata postState
    ) external view returns (bool ok, bytes memory failedConstraint);

    function computeActions(
        bytes32 policyHash,
        TreasuryState calldata state,
        MarketState calldata market
    ) external view returns (Action[] memory);
}
```

### Why Stylus

Stylus gives us:
- 10x gas savings on the loop-heavy evaluation
- Native `proptest` testing in Rust
- Strong determinism guarantees from the WASM execution environment

The Stylus contract is **non-upgradable**. Upgrades happen by deploying a new version and migrating `PolicyRegistry` to point at it — a multisig-gated, 7-day-timelocked operation.

### Storage

PolicyEngine has **zero storage**. All state is passed in by callers. This is a deliberate design choice that makes the engine a pure function and dramatically simplifies reasoning.

## 2. PolicyRegistry

Stores policy bytecode and metadata. One registry per treasury (deployed by `TreasuryFactory`).

### Interface

```solidity
interface IPolicyRegistry {
    struct PolicyMeta {
        bytes32 hash;
        bytes32 codeHash;
        address author;
        uint64  activatedAt;
        uint64  proposedAt;
        bool    active;
        bytes32[] hardConstraintIds;
    }

    function activePolicy() external view returns (bytes32 hash, PolicyMeta memory);

    function getPolicy(bytes32 hash) external view returns (
        bytes memory bytecode,
        PolicyMeta memory meta
    );

    function proposeUpdate(bytes calldata newBytecode) external returns (bytes32 newHash);

    function activateUpdate(bytes32 newHash) external; // only safe, after timelock

    function getHardConstraints(bytes32 policyHash) external view returns (bytes32[] memory);
}
```

### Storage Layout

```solidity
// 7-day update timelock for policy changes
uint256 public constant POLICY_UPDATE_TIMELOCK = 7 days;

mapping(bytes32 => bytes)      private _policyBytecode;
mapping(bytes32 => PolicyMeta) private _policyMeta;
bytes32                        public  activePolicyHash;
bytes32                        public  pendingPolicyHash;
uint64                         public  pendingActivatedAt;

address public owner;               // the Safe
address public verifier;            // PolicyVerifier contract
address public hardConstraintsLib;  // library of standard constraints
```

### Events

```solidity
event PolicyProposed(bytes32 indexed newHash, bytes32 indexed previousHash, address author);
event PolicyActivated(bytes32 indexed hash, bytes32 indexed previousHash);
event PolicyRejected(bytes32 indexed hash, bytes reason);
```

## 3. ProposalRegistry

Receives proposals from the Execution Agent, calls PolicyEngine for verdicts, manages timelock, and surfaces approved proposals to Safe.

### Interface

```solidity
interface IProposalRegistry {
    enum ProposalState { Pending, Approved, Rejected, Executed, Cancelled, Expired }

    struct Proposal {
        bytes32 id;
        address proposer;          // agent address
        bytes32 policyHash;
        bytes32 marketStateHash;
        Action[] actions;
        bytes32 dryRunResultHash;
        uint64  submittedAt;
        uint64  expiresAt;
        uint64  earliestExecution;
        ProposalState state;
        bytes32 verdictHash;
    }

    function submitProposal(
        bytes32 policyHash,
        bytes32 marketStateHash,
        Action[] calldata actions,
        bytes32 dryRunResultHash,
        bytes calldata agentSig
    ) external returns (bytes32 proposalId);

    function approveProposal(bytes32 proposalId) external; // only Safe
    function cancelProposal(bytes32 proposalId, string calldata reason) external; // only guardian
    function executeProposal(bytes32 proposalId) external;  // permissionless, after timelock

    function getProposal(bytes32 id) external view returns (Proposal memory);
    function listPending() external view returns (bytes32[] memory);
}
```

### Storage Layout

```solidity
mapping(bytes32 => Proposal) private _proposals;
bytes32[]                    private _pendingIds;
mapping(bytes32 => uint256)  private _pendingIdx;

uint64  public constant PROPOSAL_TTL  = 7 days;
uint64  public          executionTimelock = 24 hours;
uint256 public constant MIN_AGENT_BOND  = 0.01 ether;
mapping(address => uint256) public agentBonds;

address public engine;           // PolicyEngine
address public policyRegistry;
address public vault;
address public guardian;
address public safe;
mapping(address => bool) public authorizedAgents;
```

### Events

```solidity
event ProposalSubmitted(bytes32 indexed id, address indexed proposer, bytes32 policyHash);
event ProposalApproved(bytes32 indexed id, address indexed approver);
event ProposalRejected(bytes32 indexed id, bytes reason);
event ProposalCancelled(bytes32 indexed id, string reason);
event ProposalExecuted(bytes32 indexed id, bytes32 postStateHash);
event ProposalExpired(bytes32 indexed id);
event AgentBondSlashed(address indexed agent, uint256 amount, bytes32 indexed proposalId);
```

### Slashing Conditions

To prevent agent spam, agents post a bond. Bond is slashed if:
- Agent submits a proposal that PolicyEngine rejects with reason `MALFORMED`
- Agent submits a proposal whose `dryRunResultHash` does not match on-chain re-simulation at execution time

Slashed bond goes to the treasury.

## 4. TreasuryVault

Custodies funds, dispatches actions to adapters. The single point of custody.

### Interface

```solidity
interface ITreasuryVault {
    struct AssetEntry {
        address token;
        uint8   tokenType; // 0 = ERC20, 1 = ERC4626, 2 = wrapped position
        bytes32 adapter;   // bytes32(0) for direct ERC20
    }

    function getState() external view returns (AssetEntry[] memory, uint256[] memory balances);
    function getNAV() external view returns (uint256 totalNAV_usdc);

    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount, address to) external; // only safe + after timelock

    function executeApproved(bytes32 proposalId) external; // permissionless, calls back into ProposalRegistry
    function emergencyPause() external; // guardian
    function emergencyUnpause() external; // safe

    function registerAsset(AssetEntry calldata) external; // safe
    function deregisterAsset(address token) external; // safe + timelock
}
```

### Storage Layout

```solidity
struct AssetEntry {
    address token;
    uint8   tokenType;
    bytes32 adapter;
    bool    active;
    uint64  registeredAt;
}

mapping(address => AssetEntry) public assets;
address[] public assetList;

address public safe;
address public guardian;
address public proposalRegistry;
address public engine;
address public taxEngine;
address public oracleAggregator;

bool public paused;
uint256 public lastActionAt;
uint256 public totalMovement24h;          // sliding window
mapping(uint256 => uint256) public movementByHour;  // ring buffer

mapping(bytes32 => bool) public executedProposals;  // idempotency
```

### `executeApproved` Detailed Flow

```solidity
function executeApproved(bytes32 proposalId) external nonReentrant whenNotPaused {
    require(!executedProposals[proposalId], "already executed");

    Proposal memory p = IProposalRegistry(proposalRegistry).getProposal(proposalId);
    require(p.state == ProposalState.Approved, "not approved");
    require(block.timestamp >= p.earliestExecution, "timelock");
    require(block.timestamp <= p.expiresAt, "expired");

    // Re-evaluate at execution time — state may have moved
    Verdict memory v = IPolicyEngine(engine).evaluate(
        p.policyHash,
        _treasuryStateHash(),
        _liveMarketStateHash(),
        p.actions
    );
    require(v.kind == VerdictKind.Approve, "stale verdict");

    // Dispatch each action
    for (uint256 i = 0; i < p.actions.length; i++) {
        _dispatch(p.actions[i]);
    }

    // Hook tax engine
    ITaxEngine(taxEngine).recordExecution(proposalId, p.actions);

    // Mark executed
    executedProposals[proposalId] = true;
    IProposalRegistry(proposalRegistry).markExecuted(proposalId, _treasuryStateHash());

    emit Executed(proposalId);
}
```

### Events

```solidity
event AssetRegistered(address indexed token, bytes32 adapter);
event AssetDeregistered(address indexed token);
event Executed(bytes32 indexed proposalId);
event ActionDispatched(uint8 indexed actionType, address indexed adapter, bytes data);
event EmergencyPaused(address by);
event EmergencyUnpaused(address by);
```

## 5. Adapters

Adapters translate generic `Action` types into protocol-specific calls. Each adapter implements `IAdapter`:

```solidity
interface IAdapter {
    function adapterId() external view returns (bytes32);
    function supportedActions() external view returns (uint8[] memory);
    function execute(Action calldata a) external returns (bytes memory result);
    function simulate(Action calldata a, TreasuryState calldata state)
        external view returns (TreasuryState memory postState);
}
```

The vault calls `execute` only after the proposal has cleared PolicyEngine + multisig + timelock. The adapter's `simulate` is called by the off-chain Execution Agent.

### v0.5 Adapters

| Adapter | Actions supported | Notes |
|---|---|---|
| `ERC20Adapter` | TRANSFER, SWAP_UNISWAP_V3 | Default for plain tokens |
| `AaveAdapter` | SUPPLY, WITHDRAW, BORROW, REPAY | Aave V3 on Arbitrum |
| `PendleAdapter` | BUY_PT, SELL_PT, BUY_YT, SELL_YT | Pendle on Arbitrum |
| `RobinhoodRWAAdapter` | BUY_RWA, SELL_RWA, REDEEM_RWA | Robinhood Chain testnet |
| `SafeWalletAdapter` | TRANSFER_TO_SUBTREASURY | Sub-treasury federation |

### Action Type

```solidity
struct Action {
    uint8   kind;       // see ActionKind enum
    address adapter;
    address asset;
    uint256 amount;
    bytes   params;     // adapter-specific
}

enum ActionKind {
    NOOP,
    TRANSFER,
    SWAP,
    SUPPLY,
    WITHDRAW,
    BORROW,
    REPAY,
    BUY_RWA,
    SELL_RWA,
    REDEEM_RWA,
    BUY_PT,
    SELL_PT,
    SET_FLAG
}
```

## 6. TaxEngine

Records tax events at execution time. Does not modify state; classifies and emits.

### Interface

```solidity
interface ITaxEngine {
    enum TaxEventKind {
        REALIZED_GAIN,
        REALIZED_LOSS,
        DIVIDEND,
        STAKING_REWARD,
        CORPORATE_ACTION,
        INTERNAL_TRANSFER
    }

    struct TaxEvent {
        bytes32 id;
        bytes32 proposalId;
        uint64  occurredAt;
        TaxEventKind kind;
        address asset;
        uint256 amount;
        uint256 costBasis;        // for realized gain/loss
        uint256 proceedsUsd6;     // proceeds in USD 6-decimal
        int256  realizedPnlUsd6;  // realized PnL in USD 6-decimal
        uint8   lotMethod;        // 0=FIFO, 1=LIFO, 2=HIFO at time of event
        bytes8  jurisdiction;     // ISO-3166-1 alpha-2 (e.g. "US", "GB", "DE")
        bytes32 metadata;         // hash of extended metadata stored off-chain
    }

    function recordExecution(bytes32 proposalId, Action[] calldata actions) external;
    function recordCorporateAction(address asset, TaxEventKind kind, uint256 amount, bytes32 metadata) external;
    function exportPeriod(uint64 startTs, uint64 endTs) external view returns (TaxEvent[] memory);

    function setJurisdiction(bytes8 code) external; // safe
    function setLotMethod(uint8 method) external; // safe; FIFO=0, LIFO=1, HIFO=2

    function jurisdiction() external view returns (bytes8);
    function lotMethod() external view returns (uint8);
}
```

### Storage

```solidity
TaxEvent[] private _events;
mapping(bytes32 => uint256[]) private _eventsByProposal;
mapping(address => Lot[])     private _lotsByAsset;

bytes8 public jurisdiction;
uint8  public lotMethod;
address public safe;
address public vault;
```

### Cost Basis Tracking

Lots are tracked per-asset using the configured method (FIFO/LIFO/HIFO). On a `SWAP` or `SELL_RWA`, the engine matches the outflow against lots, computes realized gain/loss, and emits `TaxEvent`.

### Events

```solidity
event TaxEventRecorded(
    bytes32 indexed id,
    bytes32 indexed proposalId,
    TaxEventKind kind,
    address indexed asset,
    uint256 amount,
    int256  realizedPnL
);
event JurisdictionChanged(bytes8 from, bytes8 to);
event LotMethodChanged(uint8 from, uint8 to);
```

## 7. OracleAggregator

Wraps Chainlink + Pyth feeds with freshness and deviation guards.

### Interface

```solidity
interface IOracleAggregator {
    struct PriceQuote {
        address asset;
        uint256 priceUsd6;        // USD with 6 decimals
        uint64  observedAt;
        uint8   sourceCount;
        uint32  maxDeviationBps;
    }

    function priceOf(address asset) external view returns (PriceQuote memory);
    function snapshot(address[] calldata assets) external view returns (PriceQuote[] memory);

    function setFeed(address asset, address chainlinkFeed, bytes32 pythId) external; // safe
    function setMaxStaleness(uint32 seconds_) external; // safe
    function setMinSources(uint8 count) external; // safe
}
```

### Validation Logic

Every quote enforces:
1. Freshness: `block.timestamp - observedAt < maxStaleness`
2. Source count: at least `minSources` feeds reporting
3. Deviation: between any two sources, deviation < `maxDeviationBps`

A failing quote reverts. PolicyEngine cannot evaluate without valid oracle data, so failures are loud and fail-closed.

## 8. TreasuryFactory

One-shot deployment for a new treasury.

```solidity
interface ITreasuryFactory {
    struct DeployConfig {
        address safe;
        address guardian;
        bytes32 initialPolicyHash;
        bytes   initialPolicyBytecode;
        bytes32[] hardConstraintIds;
        bytes8 jurisdiction;
        uint8  lotMethod;
        address[] initialAssets;
        address[] authorizedAgents;
    }

    function deployTreasury(DeployConfig calldata cfg) external returns (
        address vault,
        address policyRegistry,
        address proposalRegistry,
        address taxEngine
    );
}
```

The factory deploys all four contracts atomically with the correct wiring, registers initial policy, sets initial hard constraints, and registers initial agents. No partial state is possible.

## 9. Storage Slot Discipline

For every contract:
- No unstructured storage slots
- All upgradeable paths use a separate `Initializable` pattern (OpenZeppelin)
- Storage layouts are documented in the contract NatSpec with explicit slot numbers
- Storage gap arrays are placed at the end of every contract for future-proof additions

## 10. Reentrancy & Re-entry Protections

- `TreasuryVault.executeApproved` uses `nonReentrant` modifier
- `ProposalRegistry.executeProposal` re-checks state on entry; cannot be tricked into double-execution by adapter callbacks
- `adapter.execute()` calls are made with strict gas limits
- Pull-pattern for any external value transfers where possible

## 11. Upgradability Posture

| Contract | Upgradable? | How |
|---|---|---|
| PolicyEngine (Stylus) | No (deploy new + migrate registry pointer) | 7-day timelock + Safe vote |
| PolicyRegistry | Limited (only `verifier` pointer) | Safe + 7-day timelock |
| ProposalRegistry | Limited (only configurable params: timelock, TTL, bond) | Safe + 24h timelock |
| TreasuryVault | **No** | Migration to v2 vault is opt-in by treasury owner |
| Adapters | Per-adapter, by toggling allowlist | Safe + 24h timelock |
| TaxEngine | Limited (jurisdiction, lot method) | Safe |
| OracleAggregator | Limited (feed setters) | Safe |

The non-upgradable TreasuryVault is intentional. It is the highest-risk contract; we minimize attack surface by making the bytecode immutable.

## 12. Audit Surface (for transparency)

The contracts we expect to be audited first:

1. **PolicyEngine (Stylus)** — most logic, highest risk
2. **TreasuryVault** — custody
3. **ProposalRegistry** — authorization flow
4. **OracleAggregator** — gates everything

Adapters are simpler and audited after the core.

We will engage Trail of Bits and OpenZeppelin for parallel audits before mainnet. Bug bounty launches on Immunefi with the audit report.
