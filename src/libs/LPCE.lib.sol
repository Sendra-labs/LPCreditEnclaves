// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { SRPELib } from "srpe/src/libs/SRPE/SRPE.lib.sol";

library LPCE {

    // DATA STRUCTS

    /// @notice One LP pair. Order does not matter: the ruler accepts either orientation.
    struct TokenPair {
        address tokenA;
        address tokenB;
    }

    /// @dev Bits in `EnclavePolicy.blockedActions`. A set bit drops that open from the ruler,
    ///      so the call reverts. Exits are never in this mask. Zero blocks nothing.
    uint8 internal constant BLOCK_LP = 1;
    uint8 internal constant BLOCK_SPOT = 2;
    uint8 internal constant BLOCK_SUPPLY = 4;
    uint8 internal constant BLOCK_LOOP = 8;
    uint8 internal constant BLOCK_SHORT = 16;
    uint8 internal constant BLOCK_LEVERAGE = 32;
    uint8 internal constant BLOCK_BASKET = 64;

    /// @notice Optional limits baked into the enclave at deploy. Zero means that limit is off.
    ///         Spot buys use `allowedTokens` on the enclave.
    ///         Aave supply, loop, short and borrow-to-LP each have their own asset list.
    /// @dev Drawdown, exposure, losing streak and open positions are the operator's Sendra pulse.
    ///      The factory checks them when the operator is named or accepts. The same ceilings are
    ///      SRPE rules on every open that stays enabled, so a pulse that later falls outside
    ///      reverts the next open. Results opened here are credited to that operator pulse.
    ///      Exits do not carry these rules.
    ///      `maxLoops == 0` adds no loop rule. A real loop starts at 1; the desk rejects 0.
    ///      An empty asset list adds no allowlist. `blockedActions` removes the open entirely.
    struct EnclavePolicy {
        TokenPair[] allowedPairs;
        uint256 cooldownSeconds;
        uint256 maxDrawdown;
        uint256 maxExposure;
        uint256 maxConsecutiveLosses;
        uint256 maxOpenPositions;
        uint16 maxBorrowBps;
        uint8 maxLoops;
        uint24 maxLpFee;
        address[] allowedSupplyTokens;
        address[] allowedLoopTokens;
        address[] allowedShortTokens;
        address[] allowedLeverageTokens;
        address[] allowedBasketTokens;
        uint8 blockedActions;
    }

    struct Enclave {
        address operator;
        address lender;
        address sendraExecutor;
        bool isPaused;
        bool isDeposited;
        uint256 creditInUsd;
        uint256 operatorFee;
        uint256 lenderPositionId; // sendra position id of the lender
        uint256 operatorPositionId; // sendra position id of the operator
        uint256 batchId;
        uint256 maxUsdcPerTx;
        uint256 minUsdcPerTx;
        uint256 deadline;
        uint256 rpfpId;
        string description;
        address[] allowedTokens;
        EnclavePolicy policy;
    }


    // INPUTS STRUCTS

    struct CreateEnclaveParams {
        uint256 creditInUsd;
        uint256 maxUsdcPerTx;
        uint256 minUsdcPerTx;
        uint256 deadline; // date in unix timestamp when operations stop being allowed
        uint256 operatorFee; // % of the profit that the operator takes
        address[] allowedTokens;
        address allowedOperator;
        address lender;
        string description;
        EnclavePolicy policy;
    }
    
}