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
        // CAPITAL
        /// @notice Total capital deposited across all positions, ever.
        /// @dev Denominated in the base accounting unit (e.g. USDC with 6 decimals).
        uint256 totalCapitalIn; // 0
        /// @notice Total capital withdrawn across all closed positions, including PnL.
        /// @dev ROI = (totalCapitalOut - totalCapitalIn) / totalCapitalIn
        uint256 totalCapitalOut; // 1
        /// @notice Highest simultaneous capital at risk ever recorded across open positions.
        /// @dev Updated on position open if current total exposure exceeds the stored peak.
        uint256 peakSimultaneousExposure; // 2
        uint256 currentExposure; // 3
        // PNL
        /// @notice Sum of realized PnL across all closed positions. Can be negative.
        int256 cumulativeRealizedPnl; // 4
        /// @notice Sum of PnL from winning positions only (PnL > 0).
        uint256 grossProfit; // 5
        /// @notice Sum of absolute PnL from losing positions only (PnL < 0), stored as positive.
        uint256 grossLoss; // 6
        /// @notice Highest value ever reached by cumulativeRealizedPnl. Always >= 0.
        int256 highWaterMark; // 7
        /// @notice Largest drop from highWaterMark ever recorded, stored as a positive magnitude.
        uint256 maxDrawdown; // 8
        // ACTIVITY
        /// @notice Total number of positions opened, including currently active ones.
        uint256 totalPositionsOpened; // 9
        /// @notice Total number of positions fully closed.
        uint256 totalPositionsClosed; // 10
        /// @notice Number of closed positions with a positive realized PnL.
        uint256 winCount; // 11
        /// @notice Number of closed positions with a negative or zero realized PnL.
        uint256 lossCount; // 12
        /// @notice Cumulative duration in seconds of all closed positions.
        uint256 totalDurationSeconds; // 13
        // TIME
        /// @notice Timestamp of the user's first ever position open on Sendra.
        uint256 firstActivityTimestamp; // 14
        /// @notice Timestamp of the most recent closed position.
        uint256 lastActivityTimestamp; // 15
        // RISK
        /// @notice Total number of liquidation events suffered across all positions.
        uint256 totalLiquidationEvents; // 16
        /// @notice Current consecutive loss streak (resets to 0 on any winning position).
        uint256 consecutiveLosses; // 17
        /// @notice Longest consecutive loss streak ever recorded for this user.
        uint256 maxConsecutiveLosses; // 18
        /// @notice Total capital deposited across all losing positions.
        uint256 totalLosingCapitalIn; // 19
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
