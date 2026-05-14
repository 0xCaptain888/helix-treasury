// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title IOracleAggregator
interface IOracleAggregator {
    struct PriceQuote {
        address asset;
        uint256 priceUsd6;
        uint64 observedAt;
        uint8 sourceCount;
        uint32 maxDeviationBps;
    }

    event FeedSet(address indexed asset, address chainlinkFeed, bytes32 pythId);
    event MaxStalenessSet(uint32 newSeconds);
    event MinSourcesSet(uint8 newCount);

    function priceOf(address asset) external view returns (PriceQuote memory);
    function getPrice(address asset) external view returns (uint256 priceUsdc6, uint256 updatedAt);
    function snapshot(address[] calldata assets) external view returns (PriceQuote[] memory);

    function setFeed(address asset, address chainlinkFeed, bytes32 pythId) external;
    function setMaxStaleness(uint32 secondsValue) external;
    function setMinSources(uint8 count) external;

    function maxStaleness() external view returns (uint32);
    function minSources() external view returns (uint8);
}
