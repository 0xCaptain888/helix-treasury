// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title CorporateActionListener
/// @notice Listens for corporate action events on Robinhood Chain (dividends, splits, mergers,
///         delistings) and dispatches them to the RobinhoodRWAAdapter for processing.
/// @dev See docs/07-integrations.md §4.2. This contract is deployed on Robinhood Chain
///         and bridges events to the adapter.
contract CorporateActionListener {
    address public immutable rwaAdapter;
    address public guardian;

    /// @notice Tracks processed event hashes to prevent double-processing.
    mapping(bytes32 => bool) public processedEvents;

    event CorporateActionReceived(bytes32 indexed eventHash, uint8 actionType, address indexed asset);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "CorporateActionListener: not guardian");
        _;
    }

    constructor(address _rwaAdapter, address _guardian) {
        require(_rwaAdapter != address(0), "CorporateActionListener: zero adapter");
        rwaAdapter = _rwaAdapter;
        guardian = _guardian;
    }

    /// @notice Process a dividend distribution event.
    /// @param asset The token that received a dividend.
    /// @param amount The dividend amount in the token's native decimals.
    /// @param eventHash Unique hash of the corporate action event (for idempotency).
    function processDividend(address asset, uint256 amount, bytes32 eventHash) external onlyGuardian {
        require(!processedEvents[eventHash], "CorporateActionListener: already processed");
        processedEvents[eventHash] = true;

        // Forward to RWA adapter
        (bool success,) = rwaAdapter.call(
            abi.encodeWithSignature("onDividend(address,uint256)", asset, amount)
        );
        require(success, "CorporateActionListener: dividend forward failed");

        emit CorporateActionReceived(eventHash, 0, asset);
    }

    /// @notice Process a stock split event.
    function processSplit(
        address asset,
        uint256 oldBalance,
        uint256 newBalance,
        uint256 ratio,
        bytes32 eventHash
    ) external onlyGuardian {
        require(!processedEvents[eventHash], "CorporateActionListener: already processed");
        processedEvents[eventHash] = true;

        (bool success,) = rwaAdapter.call(
            abi.encodeWithSignature(
                "onSplit(address,uint256,uint256,uint256)",
                asset, oldBalance, newBalance, ratio
            )
        );
        require(success, "CorporateActionListener: split forward failed");

        emit CorporateActionReceived(eventHash, 1, asset);
    }

    /// @notice Process a merger / acquisition event.
    function processMerger(address oldAsset, address newAsset, uint256 ratio, bytes32 eventHash)
        external
        onlyGuardian
    {
        require(!processedEvents[eventHash], "CorporateActionListener: already processed");
        processedEvents[eventHash] = true;

        (bool success,) = rwaAdapter.call(
            abi.encodeWithSignature("onMerger(address,address,uint256)", oldAsset, newAsset, ratio)
        );
        require(success, "CorporateActionListener: merger forward failed");

        emit CorporateActionReceived(eventHash, 2, oldAsset);
    }

    /// @notice Process a delisting event.
    function processDelisting(address asset, bytes32 eventHash) external onlyGuardian {
        require(!processedEvents[eventHash], "CorporateActionListener: already processed");
        processedEvents[eventHash] = true;

        (bool success,) = rwaAdapter.call(
            abi.encodeWithSignature("onDelisting(address)", asset)
        );
        require(success, "CorporateActionListener: delisting forward failed");

        emit CorporateActionReceived(eventHash, 3, asset);
    }

    function setGuardian(address _guardian) external onlyGuardian {
        guardian = _guardian;
    }
}
