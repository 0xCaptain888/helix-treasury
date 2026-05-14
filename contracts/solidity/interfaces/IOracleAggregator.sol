// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IOracleAggregator
/// @notice Aggregates Chainlink + Pyth (+ Robinhood RWA oracle) with freshness and deviation guards.
/// @dev Every quote enforces freshness, source count, and inter-source deviation. Failing quotes
///      revert. See docs/04-contracts.md §7 and docs/07-integrations.md §5.
interface IOracleAggregator {
    struct PriceQuote {
        address asset;
        uint256 priceUsd6; // 6 decimals
        uint64 observedAt;
        uint8 sourceCount;
        uint32 maxDeviationBps;
    }

    event FeedSet(address indexed asset, address chainlinkFeed, bytes32 pythId);
    event MaxStalenessSet(uint32 newSeconds);
    event MinSourcesSet(uint8 newCount);

    function priceOf(address asset) external view returns (PriceQuote memory);
    function snapshot(address[] calldata assets) external view returns (PriceQuote[] memory);

    function setFeed(address asset, address chainlinkFeed, bytes32 pythId) external; // safe
    function setMaxStaleness(uint32 secondsValue) external; // safe
    function setMinSources(uint8 count) external; // safe

    function maxStaleness() external view returns (uint32);
    function minSources() external view returns (uint8);
}
