// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IOracleAggregator} from "./interfaces/IOracleAggregator.sol";

/// @title OracleAggregator
/// @notice Wraps Chainlink + Pyth (+ optional Robinhood RWA oracle) with freshness and
///         inter-source deviation guards. Failing quotes revert.
/// @dev See docs/04-contracts.md §7 and docs/07-integrations.md §5.
contract OracleAggregator is IOracleAggregator {
    struct Feed {
        address chainlinkFeed;
        bytes32 pythId;
        address rwaOracle;
        bool active;
    }

    mapping(address => Feed) public feeds;
    uint32 public override maxStaleness = 1 hours;
    uint8 public override minSources = 2;
    uint32 public maxDeviationBps = 100; // 1%

    address public safe;
    address public guardian;
    address public chainlinkRegistry;
    address public pyth;

    uint256[40] private __gap;

    modifier onlySafe() {
        require(msg.sender == safe, "OracleAggregator: not safe");
        _;
    }

    constructor(address _chainlinkRegistry, address _pyth, address _safe, address _guardian) {
        require(_safe != address(0), "OracleAggregator: zero safe");
        chainlinkRegistry = _chainlinkRegistry;
        pyth = _pyth;
        safe = _safe;
        guardian = _guardian;
    }

    /// @notice Returns the median price from available oracle sources for the given asset.
    /// @dev Gathers quotes from Chainlink and Pyth (and RWA oracle if set), filters by freshness,
    ///      requires >= minSources fresh, computes median, and enforces inter-source deviation.
    function priceOf(address asset) external view override returns (PriceQuote memory) {
        Feed storage f = feeds[asset];
        require(f.active, "OracleAggregator: no feed");

        uint256[] memory prices = new uint256[](3);
        uint64[] memory timestamps = new uint64[](3);
        uint8 count = 0;

        // 1. Chainlink
        if (f.chainlinkFeed != address(0)) {
            (uint256 clPrice, uint64 clTs) = _readChainlink(f.chainlinkFeed);
            if (block.timestamp - clTs <= maxStaleness) {
                prices[count] = clPrice;
                timestamps[count] = clTs;
                count++;
            }
        }

        // 2. Pyth
        if (f.pythId != bytes32(0) && pyth != address(0)) {
            (uint256 pythPrice, uint64 pythTs) = _readPyth(f.pythId);
            if (block.timestamp - pythTs <= maxStaleness) {
                prices[count] = pythPrice;
                timestamps[count] = pythTs;
                count++;
            }
        }

        // 3. RWA oracle (optional)
        if (f.rwaOracle != address(0)) {
            (uint256 rwaPrice, uint64 rwaTs) = _readRwaOracle(f.rwaOracle, asset);
            if (block.timestamp - rwaTs <= maxStaleness) {
                prices[count] = rwaPrice;
                timestamps[count] = rwaTs;
                count++;
            }
        }

        require(count >= minSources, "OracleAggregator: insufficient fresh sources");

        // Compute median
        uint256 median = _median(prices, count);

        // Check pairwise deviation
        for (uint8 i = 0; i < count; i++) {
            uint256 deviation = prices[i] > median
                ? ((prices[i] - median) * 10_000) / median
                : ((median - prices[i]) * 10_000) / median;
            require(deviation <= maxDeviationBps, "OracleAggregator: deviation too high");
        }

        // Find oldest timestamp
        uint64 oldest = timestamps[0];
        for (uint8 i = 1; i < count; i++) {
            if (timestamps[i] < oldest) oldest = timestamps[i];
        }

        return PriceQuote({
            asset: asset,
            priceUsd6: median,
            observedAt: oldest,
            sourceCount: count,
            maxDeviationBps: maxDeviationBps
        });
    }

    function snapshot(address[] calldata assets) external view override returns (PriceQuote[] memory quotes) {
        quotes = new PriceQuote[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            quotes[i] = this.priceOf(assets[i]);
        }
    }

    function setFeed(address asset, address chainlinkFeed, bytes32 pythId) external override onlySafe {
        feeds[asset] = Feed({chainlinkFeed: chainlinkFeed, pythId: pythId, rwaOracle: address(0), active: true});
        emit FeedSet(asset, chainlinkFeed, pythId);
    }

    /// @notice Convenience setter for Chainlink-only feeds (used during deployment).
    function setChainlinkFeed(address asset, address chainlinkFeed) external onlySafe {
        feeds[asset].chainlinkFeed = chainlinkFeed;
        if (!feeds[asset].active) feeds[asset].active = true;
        emit FeedSet(asset, chainlinkFeed, feeds[asset].pythId);
    }

    function setRwaOracle(address asset, address rwaOracle) external onlySafe {
        feeds[asset].rwaOracle = rwaOracle;
    }

    function setMaxStaleness(uint32 secondsValue) external override onlySafe {
        require(secondsValue >= 60 && secondsValue <= 24 hours, "OracleAggregator: bad staleness");
        maxStaleness = secondsValue;
        emit MaxStalenessSet(secondsValue);
    }

    function setMinSources(uint8 count) external override onlySafe {
        require(count >= 1 && count <= 5, "OracleAggregator: bad count");
        minSources = count;
        emit MinSourcesSet(count);
    }

    // ──────────── Internal oracle readers ────────────

    /// @dev Reads price from a Chainlink AggregatorV3 feed. Returns (priceUsd6, timestamp).
    function _readChainlink(address feed) internal view returns (uint256 priceUsd6, uint64 timestamp) {
        // Chainlink AggregatorV3Interface: latestRoundData()
        // returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
        (, bytes memory data) = feed.staticcall(
            abi.encodeWithSignature("latestRoundData()")
        );
        (, int256 answer,, uint256 updatedAt,) = abi.decode(data, (uint80, int256, uint256, uint256, uint80));
        require(answer > 0, "OracleAggregator: negative chainlink price");

        // Get decimals
        (, bytes memory decData) = feed.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(decData, (uint8));

        // Normalize to 6 decimals
        if (decimals > 6) {
            priceUsd6 = uint256(answer) / (10 ** (decimals - 6));
        } else {
            priceUsd6 = uint256(answer) * (10 ** (6 - decimals));
        }
        timestamp = uint64(updatedAt);
    }

    /// @dev Reads price from Pyth oracle. Returns (priceUsd6, timestamp).
    function _readPyth(bytes32 pythId) internal view returns (uint256 priceUsd6, uint64 timestamp) {
        // IPyth.getPriceUnsafe(bytes32 id) returns Price { int64 price, uint64 conf, int32 expo, uint publishTime }
        (, bytes memory data) = pyth.staticcall(
            abi.encodeWithSignature("getPriceUnsafe(bytes32)", pythId)
        );
        (int64 price,, int32 expo, uint256 publishTime) = abi.decode(data, (int64, uint64, int32, uint256));
        require(price > 0, "OracleAggregator: negative pyth price");

        // Convert to 6-decimal USD
        // price * 10^(6 + expo) gives us the value in 6-decimal format
        int32 targetExpo = int32(6) + expo;
        if (targetExpo >= 0) {
            priceUsd6 = uint256(int256(price)) * (10 ** uint32(targetExpo));
        } else {
            priceUsd6 = uint256(int256(price)) / (10 ** uint32(-targetExpo));
        }
        timestamp = uint64(publishTime);
    }

    /// @dev Reads price from an RWA oracle. Returns (priceUsd6, timestamp).
    function _readRwaOracle(address oracle, address asset) internal view returns (uint256 priceUsd6, uint64 timestamp) {
        (, bytes memory data) = oracle.staticcall(
            abi.encodeWithSignature("getPrice(address)", asset)
        );
        (priceUsd6, timestamp) = abi.decode(data, (uint256, uint64));
        require(priceUsd6 > 0, "OracleAggregator: zero rwa price");
    }

    // ──────────── Math helpers ────────────

    function _median(uint256[] memory values, uint8 count) internal pure returns (uint256) {
        if (count == 1) return values[0];
        if (count == 2) return (values[0] + values[1]) / 2;
        // count == 3: sort and take middle
        uint256 a = values[0];
        uint256 b = values[1];
        uint256 c = values[2];
        if (a > b) (a, b) = (b, a);
        if (b > c) (b, c) = (c, b);
        if (a > b) (a, b) = (b, a);
        return b;
    }
}
