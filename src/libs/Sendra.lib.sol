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
        /*0*/ uint256 totalCapitalIn; // lender
        /*1*/ uint256 totalCapitalOut; // lender
        /*2*/ uint256 peakSimultaneousExposure; // lender
        /*3*/ uint256 currentExposure; // lender
        /*4*/ int256 cumulativeRealizedPnl; // lender
        /*5*/ uint256 grossProfit; // lender
        /*6*/ uint256 grossLoss; // lender
        /*7*/ int256 highWaterMark; // lender
        /*8*/ uint256 maxDrawdown; // lender
        /*9*/ uint256 totalPositionsOpened; // operator each and lender
        /*10*/ uint256 totalPositionsClosed; // operator each and lender
        /*11*/ uint256 winCount; // operator each and lender
        /*12*/ uint256 lossCount; // operator each and lender
        /*13*/ uint256 totalDurationSeconds; // operator each and lender
        /*14*/ uint256 firstActivityTimestamp; // operator and lender
        /*15*/ uint256 lastActivityTimestamp; // operator and lender
        /*16*/ uint256 totalLiquidationEvents; // none
        /*17*/ uint256 consecutiveLosses; // operator each 
        /*18*/ uint256 maxConsecutiveLosses; // operator
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
