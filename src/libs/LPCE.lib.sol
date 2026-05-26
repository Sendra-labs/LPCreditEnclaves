// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { SRPELib } from "srpe/src/libs/SRPE/SRPE.lib.sol";

library LPCE {

    // DATA STRUCTS

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
        string description;
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
    }
    
}