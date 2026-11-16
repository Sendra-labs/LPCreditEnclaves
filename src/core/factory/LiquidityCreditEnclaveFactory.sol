// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LPCE } from "../../libs/LPCE.lib.sol";
import { RPFPDeployer } from "srpe/src/core/RPFPDeployer.sol";
import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { SRPELib } from "srpe/src/libs/SRPE/SRPE.lib.sol";
import { LiquidityLogic } from "../execution/LiquidityLogic.sol";
import { EnclaveRuleBook } from "../../libs/EnclaveRuleBook.sol";
import { SendraLib } from "../../libs/Sendra.lib.sol";
import { ISendraStorage } from "../../interfaces/iSendraCore/ISendraStorage.sol";
import { EnclavesStorage } from "../storage/EnclavesStorage.sol";
import { AccessControlInter } from "../storage/security/AccessControlInter.sol";
import { UniversalExecutor } from "srpe/src/core/execution/UniversalExecutor.sol";

/*
Deployment instructions:
1. this contract must be Sendra Protocol Contract in Sendra Roles
*/

contract LiquidityCreditEnclaveFactory {
    
    address public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = _addressProvider;
    }

    function createEnclave(LPCE.CreateEnclaveParams memory params) public returns (uint256, address) {

        if(params.operatorFee > 100) revert OperatorFeeCannotBeGreaterThan100();

        LPCE.Enclave memory enclave = LPCE.Enclave({
                operator: params.allowedOperator,
                lender: msg.sender,
                sendraExecutor: address(0),
                isPaused: false,
                isDeposited: false,
                creditInUsd: params.creditInUsd,
                lenderPositionId: 0,
                operatorPositionId: 0,
                operatorFee: params.operatorFee,
                batchId: 0,
                maxUsdcPerTx: params.maxUsdcPerTx,
                minUsdcPerTx: params.minUsdcPerTx,
                deadline: params.deadline,
                rpfpId: 0,
                description: params.description,
                allowedTokens: params.allowedTokens,
                policy: params.policy
            });
        
        if(enclave.operator != address(0)) {
            _requireOperatorFits(enclave.operator, params.policy);

            SRPELib.Rules[] memory functionSelectorRules;
            bytes4[] memory functionSelectors;

            (functionSelectorRules, functionSelectors) = createRules(
                params.creditInUsd, 
                params.minUsdcPerTx, 
                params.maxUsdcPerTx, 
                params.deadline, 
                params.allowedOperator, 
                msg.sender,
                params.allowedTokens,
                params.policy
            );

            SRPELib.NewRPFPInputs memory deployParams;
            deployParams._type = 1;
            deployParams.implementation = address(ISendraAddressProvider(addressProvider).getAddress("LiquidityLogic"));
            deployParams.description = params.description;
            deployParams.functionSelectorRules = functionSelectorRules;
            deployParams.functionSelectors = functionSelectors;

            (address sendraExecutor, uint256 rpfpId) = RPFPDeployer(ISendraAddressProvider(addressProvider).getAddress("RPFPDeployer")).deployRPFP(deployParams); // MUST RETURN ADDRESS OF THE EXECUTOR and rpfpId

            enclave.sendraExecutor = sendraExecutor;
            enclave.rpfpId = rpfpId;

            uint256 enclaveId = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage")).createEnclave(enclave);

            AccessControlInter(ISendraAddressProvider(addressProvider).getAddress("AccessControlInter")).setIsSendraEnclave(sendraExecutor, true);

            UniversalExecutor(sendraExecutor).execute(
                SRPELib.ExecutionParams({
                targetFunction: 6, // initializeOperatorPosition Not used ¿?¿?
                rpfpId: rpfpId,
                actionData: abi.encodeWithSelector(LiquidityLogic.initializeOperatorPosition.selector)
            }));

            emit EnclaveCreated(enclaveId, sendraExecutor);

            return (enclaveId, sendraExecutor);
        } else {

            uint256 enclaveId = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage")).createEnclave(enclave);

            return (enclaveId, address(0));
        }
    }


    function acceptOffer(uint256 _batchId, uint256 _enclaveId) public {

        EnclavesStorage enclaveStorage = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"));

        LPCE.Enclave memory enclave = enclaveStorage.getEnclave(_enclaveId);
        _requireOperatorFits(msg.sender, enclave.policy);

        SRPELib.Rules[] memory functionSelectorRules;
        bytes4[] memory functionSelectors;

        (functionSelectorRules, functionSelectors) = createRules(
            enclave.creditInUsd, 
            enclave.minUsdcPerTx, 
            enclave.maxUsdcPerTx, 
            enclave.deadline, 
            msg.sender, 
            enclave.lender,
            enclave.allowedTokens,
            enclave.policy
        );

        SRPELib.NewRPFPInputs memory deployParams;
        deployParams._type = 1;
        deployParams.implementation = address(ISendraAddressProvider(addressProvider).getAddress("LiquidityLogic"));
        deployParams.description = enclave.description;
        deployParams.functionSelectorRules = functionSelectorRules;
        deployParams.functionSelectors = functionSelectors;

        (address sendraExecutor, uint256 rpfpId) = RPFPDeployer(ISendraAddressProvider(addressProvider).getAddress("RPFPDeployer")).deployRPFP(deployParams);

        AccessControlInter(ISendraAddressProvider(addressProvider).getAddress("AccessControlInter")).setIsSendraEnclave(sendraExecutor, true);

        enclaveStorage.acceptOffer(_batchId, _enclaveId, msg.sender, sendraExecutor);
        
        UniversalExecutor(sendraExecutor).execute(
            SRPELib.ExecutionParams({
            targetFunction: 6, // initializeOperatorPosition Not used ¿?¿?
            rpfpId: rpfpId,
            actionData: abi.encodeWithSelector(LiquidityLogic.initializeOperatorPosition.selector)
        }));

        emit OfferAccepted(_batchId, _enclaveId, msg.sender, sendraExecutor);
    }

    function cancelOffer(uint256 _batchId, uint256 _enclaveId) public {
        EnclavesStorage enclaveStorage = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"));
        enclaveStorage.cancelOffer(_batchId, _enclaveId, msg.sender);
        emit OfferCancelled(_batchId, _enclaveId, msg.sender);
    }

    function createRules(
            uint256 creditInUsd,
            uint256 minUsdcPerTx,
            uint256 maxUsdcPerTx,
            uint256 deadline,
            address allowedOperator,
            address allowedLender,
            address[] memory allowedTokens,
            LPCE.EnclavePolicy memory policy
        ) internal view returns (SRPELib.Rules[] memory functionSelectorRules, bytes4[] memory functionSelectors) {
        
        if(minUsdcPerTx == 0) revert MinUsdcPerTxCannotBeZero();
        if(maxUsdcPerTx < minUsdcPerTx) revert MaxUsdcPerTxCannotBeLessThanMinUsdcPerTx();
        if(maxUsdcPerTx == 0) revert MaxUsdcPerTxCannotBeZero();
        if(deadline <= block.timestamp) revert DeadlineCannotBeInThePast();
        _validateTokens(allowedTokens);
        _validateTokens(policy.allowedSupplyTokens);
        _validateTokens(policy.allowedLoopTokens);
        _validateTokens(policy.allowedShortTokens);
        _validateTokens(policy.allowedLeverageTokens);
        _validateTokens(policy.allowedBasketTokens);
        _validatePolicy(policy);

        functionSelectors = new bytes4[](21);
        functionSelectors[0] = LiquidityLogic.provideLiquidity.selector;
        functionSelectors[1] = LiquidityLogic.withdrawCredit.selector;
        functionSelectors[2] = LiquidityLogic.closePosition.selector;
        functionSelectors[3] = LiquidityLogic.depositCredit.selector;
        functionSelectors[4] = LiquidityLogic.pauseExecution.selector;
        functionSelectors[5] = LiquidityLogic.unpauseExecution.selector;
        functionSelectors[6] = LiquidityLogic.initializeOperatorPosition.selector;
        functionSelectors[7] = LiquidityLogic.revokeEnclave.selector;
        functionSelectors[8] = LiquidityLogic.provideLiquidityNoAccountingTest.selector;
        functionSelectors[9] = LiquidityLogic.buySpot.selector;
        functionSelectors[10] = LiquidityLogic.sellSpot.selector;
        functionSelectors[11] = LiquidityLogic.openSupply.selector;
        functionSelectors[12] = LiquidityLogic.openLoop.selector;
        functionSelectors[13] = LiquidityLogic.openShort.selector;
        functionSelectors[14] = LiquidityLogic.openLeveraged.selector;
        functionSelectors[15] = LiquidityLogic.closeStrategy.selector;
        functionSelectors[16] = LiquidityLogic.releaseShort.selector;
        functionSelectors[17] = LiquidityLogic.closeLeveraged.selector;
        functionSelectors[18] = LiquidityLogic.partialClose.selector;
        functionSelectors[19] = LiquidityLogic.sellHeld.selector;
        functionSelectors[20] = LiquidityLogic.openBasket.selector;

        functionSelectorRules = EnclaveRuleBook.rulesFor(
            functionSelectors,
            creditInUsd,
            minUsdcPerTx,
            maxUsdcPerTx,
            deadline,
            allowedOperator,
            allowedLender,
            address(this),
            allowedTokens,
            policy
        );
        (functionSelectors, functionSelectorRules) = EnclaveRuleBook.withoutBlocked(functionSelectors, functionSelectorRules);
    }

    /// @dev Reads the operator's pulse only when a cap is set. Zero caps skip the storage call.
    function _requireOperatorFits(address operator, LPCE.EnclavePolicy memory policy) internal view {
        if (operator == address(0)) return;
        if (
            policy.maxDrawdown == 0
                && policy.maxExposure == 0
                && policy.maxConsecutiveLosses == 0
                && policy.maxOpenPositions == 0
        ) return;
        SendraLib.GlobalAccumulators memory book = ISendraStorage(
            ISendraAddressProvider(addressProvider).getAddress("SendraStorage")
        ).getUserGlobalAccumulators(operator);
        if (!EnclaveRuleBook.operatorFits(book, policy)) revert OperatorOutsidePolicy();
    }

    function _validateTokens(address[] memory tokens) internal pure {
        if (tokens.length > SRPELib.MAX_LIST) revert TooManyTokens();
        for (uint256 i; i < tokens.length; ++i) {
            if (tokens[i] == address(0)) revert ZeroToken();
        }
    }

    function _validatePolicy(LPCE.EnclavePolicy memory policy) internal pure {
        uint256 pairCount = policy.allowedPairs.length;
        if (pairCount > SRPELib.MAX_LIST) revert TooManyPairs();
        for (uint256 i; i < pairCount; ++i) {
            address a = policy.allowedPairs[i].tokenA;
            address b = policy.allowedPairs[i].tokenB;
            if (a == address(0) || b == address(0) || a == b) revert InvalidPair();
        }
        if (policy.maxBorrowBps > 10_000) revert BorrowCapTooHigh();
    }

    event EnclaveCreated(uint256 indexed enclaveId, address indexed sendraExecutor);
    event OfferAccepted(uint256 indexed batchId, uint256 indexed enclaveId, address indexed operator, address sendraExecutor);
    event OfferCancelled(uint256 indexed batchId, uint256 indexed enclaveId, address indexed lender);

    error MinUsdcPerTxCannotBeZero();
    error MaxUsdcPerTxCannotBeLessThanMinUsdcPerTx();
    error MaxUsdcPerTxCannotBeZero();
    error DeadlineCannotBeInThePast();
    error OperatorFeeCannotBeGreaterThan100();
    error TooManyTokens();
    error TooManyPairs();
    error ZeroToken();
    error InvalidPair();
    error BorrowCapTooHigh();
    error OperatorOutsidePolicy();

}
