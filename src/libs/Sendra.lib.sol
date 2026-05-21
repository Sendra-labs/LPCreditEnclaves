// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @dev Structs aligned with protocol `Sendra.lib.sol` / `SendraStorage` for ABI-compatible reads and calls.
 *      Keep in sync with `protocol/src/lib/Sendra.lib.sol`.
 */
library SendraLib {
    
    struct Position {
        uint128 positionType;
        uint256 id;
        int256 pnl;
        bool isActive;
        bytes[] positionData;
    }

    struct GlobalAccumulators {
        uint256 totalCapitalIn;
        uint256 totalCapitalOut;
        uint256 peakSimultaneousExposure;
        uint256 currentExposure;
        int256 cumulativeRealizedPnl;
        uint256 grossProfit;
        uint256 grossLoss;
        int256 highWaterMark;
        uint256 maxDrawdown;
        uint256 totalPositionsOpened;
        uint256 totalPositionsClosed;
        uint256 winCount;
        uint256 lossCount;
        uint256 totalDurationSeconds;
        uint256 firstActivityTimestamp;
        uint256 lastActivityTimestamp;
        uint256 totalLiquidationEvents;
        uint256 consecutiveLosses;
        uint256 maxConsecutiveLosses;
    }

    struct SpecificAccumulators {
        int256 realizedPnl;
        uint256 totalCapitalIn;
        uint256 totalCapitalOut;
        uint256 winCount;
        uint256 lossCount;
        uint256 totalPositions;
        bytes[] specificMetrics;
    }

    struct UserInfoRead {
        uint256 id;
        int256 globalPnl;
        uint256 totalPositions;
        uint256 activePositions;
        uint256 transactionCount;
        bytes[] userData;
    }

    struct ProtocolStats {
        uint256 totalUsers;
        uint256 totalVolume;
        int256 totalPnl;
        uint256 totalTransactions;
        uint256 totalPositions;
        uint256 totalActivePositions;
        uint256 totalValueLocked;
    }
}
