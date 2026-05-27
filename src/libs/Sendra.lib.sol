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
        uint256 totalCapitalIn; // lender
        uint256 totalCapitalOut; // lender
        uint256 peakSimultaneousExposure; // lender
        uint256 currentExposure; // lender
        int256 cumulativeRealizedPnl; // lender
        uint256 grossProfit; // lender
        uint256 grossLoss; // lender
        int256 highWaterMark; // lender
        uint256 maxDrawdown; // lender
        uint256 totalPositionsOpened; // operator each and lender
        uint256 totalPositionsClosed; // operator each and lender
        uint256 winCount; // operator each and lender
        uint256 lossCount; // operator each and lender
        uint256 totalDurationSeconds; // operator each and lender
        uint256 firstActivityTimestamp; // operator and lender
        uint256 lastActivityTimestamp; // operator and lender
        uint256 totalLiquidationEvents;
        uint256 consecutiveLosses; // operator
        uint256 maxConsecutiveLosses; // operator
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
