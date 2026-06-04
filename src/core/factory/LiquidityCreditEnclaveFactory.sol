// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { LPCE } from "../../library/LPCE.lib.sol";
import { RPFPDeployer } from "srpe/src/core/RPFPDeployer.sol";
import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { SRPELib } from "srpe/src/libs/SRPE/SRPE.lib.sol";
import { LiquidityLogic } from "../execution/LiquidityLogic.sol";
import { EnclavesStorage } from "../storage/EnclavesStorage.sol";
import { AccessControlInter } from "../storage/security/AccessControlInter.sol";

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
                description: params.description
            });
        
        if(enclave.operator != address(0)) {
            SRPELib.Rules memory functionSelectorRules;
            bytes4[] memory functionSelectors;

            (functionSelectorRules, functionSelectors) = createRules(
                params.creditInUsd, 
                params.minUsdcPerTx, 
                params.maxUsdcPerTx, 
                params.deadline, 
                params.operatorFee, 
                params.allowedOperator, 
                msg.sender,
                params.allowedTokens
            );

            SRPELib.NewRPFPInputs memory deployParams;
            deployParams._type = 1;
            deployParams.implementation = address(ISendraAddressProvider(addressProvider).getAddress("LiquidityLogic"));
            deployParams.functionSelectorRules = functionSelectorRules;
            deployParams.functionSelectors = functionSelectors;

            (address sendraExecutor, uint256 rpfpId) = RPFPDeployer(addressProvider.getAddress("RPFPDeployer")).deployRPFP(deployParams); // MUST RETURN ADDRESS OF THE EXECUTOR and rpfpId

            enclave.sendraExecutor = sendraExecutor;
            
            uint256 enclaveId = EnclavesStorage(addressProvider.getAddress("EnclavesStorage")).createEnclave(enclave);

            AccessControlInter(addressProvider.getAddress("AccessControlInter")).setIsSendraEnclave(sendraExecutor, true);

            sendraExecutor.execute(
                SRPELib.ExecutionParams({
                targetFunction: 6, // initializeOperatorPosition Not used ¿?¿?
                rpfpId: rpfpId,
                actionData: abi.encodeWithSelector(LiquidityLogic.initializeOperatorPosition.selector)
            }));

            emit EnclaveCreated(enclaveId, sendraExecutor);

            return (enclaveId, sendraExecutor);
        } else {

            uint256 enclaveId = EnclavesStorage(addressProvider.getAddress("EnclavesStorage")).createEnclave(enclave);

            return (enclaveId, address(0));
        }
    }


    function acceptOffer(uint256 _batchId, uint256 _enclaveId) public {

        EnclavesStorage enclaveStorage = EnclavesStorage(addressProvider.getAddress("EnclavesStorage"));

        LPCE.Enclave memory enclave = enclaveStorage.getEnclave(_enclaveId);
        
        SRPELib.Rules memory functionSelectorRules;
        bytes4[] memory functionSelectors;

        (functionSelectorRules, functionSelectors) = createRules(
            enclave.creditInUsd, 
            enclave.minUsdcPerTx, 
            enclave.maxUsdcPerTx, 
            enclave.deadline, 
            enclave.operatorFee, 
            msg.sender, 
            enclave.lender,
            new address[](0)
        );

        SRPELib.NewRPFPInputs memory deployParams;
        deployParams._type = 1;
        deployParams.implementation = address(ISendraAddressProvider(addressProvider).getAddress("LiquidityLogic"));
        deployParams.functionSelectorRules = functionSelectorRules;
        deployParams.functionSelectors = functionSelectors;

        /*address sendraExecutor, uint256 rpfpId = */ RPFPDeployer(addressProvider.getAddress("RPFPDeployer")).deployRPFP(deployParams); // MUST RETURN ADDRESS OF THE EXECUTOR and rpfpId

        AccessControlInter(addressProvider.getAddress("AccessControlInter")).setIsSendraEnclave(sendraExecutor, true);

        sendraExecutor.execute(
            SRPELib.ExecutionParams({
            targetFunction: 6, // initializeOperatorPosition Not used ¿?¿?
            rpfpId: /*rpfpId*/,
            actionData: abi.encodeWithSelector(LiquidityLogic.initializeOperatorPosition.selector)
        }));

        enclaveStorage.acceptOffer(_batchId, _enclaveId, msg.sender, sendraExecutor);

        emit OfferAccepted(_batchId, _enclaveId, msg.sender, sendraExecutor);
    }

    function createRules(
            uint256 creditInUsd,
            uint256 minUsdcPerTx, 
            uint256 maxUsdcPerTx, 
            uint256 deadline, 
            uint256 operatorFee, 
            address allowedOperator,
            address allowedLender,
            address[] memory allowedTokens
        ) internal view returns (SRPELib.Rules[] memory functionSelectorRules, bytes4[] memory functionSelectors) {
        
        if(minUsdcPerTx == 0) revert MinUsdcPerTxCannotBeZero();
        if(maxUsdcPerTx < minUsdcPerTx) revert MaxUsdcPerTxCannotBeLessThanMinUsdcPerTx();
        if(maxUsdcPerTx == 0) revert MaxUsdcPerTxCannotBeZero();
        if(deadline <= block.timestamp) revert DeadlineCannotBeInThePast();

        
        functionSelectorRules = new SRPELib.Rules[](7);

        functionSelectors = new bytes4[](7);

        // Provide Liquidity
        functionSelectors[0] = LiquidityLogic.provideLiquidity.selector;

            functionSelectorRules[0] = SRPELib.Rules({
                ruleCount: 3,
                rules: new SRPELib.Rule[](3)
            });

            // Usdc amount limits
            functionSelectorRules[0].rules[0] = SRPELib.Rule({
                ruleType: 8,
                ruleData: abi.encode(minUsdcPerTx, maxUsdcPerTx),
                extraData: abi.encode(uint256(0)) // paramIndex of the usdc amount
            });
    
            // Time limit
            functionSelectorRules[0].rules[1] = SRPELib.Rule({
                ruleType: 3,
                ruleData: abi.encode(deadline, uint256(0)), 
                extraData: ""
            });


            // Allow specific operator
            functionSelectorRules[0].rules[2] = SRPELib.Rule({
                ruleType: 5,
                ruleData: abi.encode(functionSelectors[0], allowedOperator),
                extraData: ""
            });

        // withdraw credit
        functionSelectors[1] = LiquidityLogic.withdrawCredit.selector;

        functionSelectorRules[1] = SRPELib.Rules({
            ruleCount: 1,
            rules: new SRPELib.Rule[](1)
        });

            address[] memory allowedSenders = new address[](2);
            allowedSenders[0] = allowedLender;
            allowedSenders[1] = allowedOperator;

            // Withdraw Credit can be signed by the operator or the lender and logic sends the capital between both.
            functionSelectorRules[1].rules[0] = SRPELib.Rule({
                ruleType: 1,
                ruleData: abi.encode(allowedSenders),
                extraData: ""
            });


        // close position

        functionSelectors[2] = LiquidityLogic.closePosition.selector; 

        functionSelectorRules[2] = SRPELib.Rules({
            ruleCount: 1,
            rules: new SRPELib.Rule[](1)
        });

            functionSelectorRules[2].rules[0] = SRPELib.Rule({
                ruleType: 1,
                ruleData: abi.encode(allowedSenders),
                extraData: ""
            });


        // deposit credit
        functionSelectors[3] = LiquidityLogic.depositCredit.selector;

        functionSelectorRules[3] = SRPELib.Rules({
            ruleCount: 1,
            rules: new SRPELib.Rule[](1)
        });

            functionSelectorRules[3].rules[0] = SRPELib.Rule({
                ruleType: 6,
                ruleData: abi.encode(functionSelectors[3], allowedLender, uint256(0), abi.encode(creditInUsd)), // paramIndex of the creditInUsd
                extraData: ""
            });


        // pause execution
        functionSelectors[4] = LiquidityLogic.pauseExecution.selector;

        functionSelectorRules[4] = SRPELib.Rules({
            ruleCount: 1,
            rules: new SRPELib.Rule[](1)
        });

            functionSelectorRules[4].rules[0] = SRPELib.Rule({
                ruleType: 5,
                ruleData: abi.encode(functionSelectors[4], allowedLender),
                extraData: ""
            });

        // unpause execution
        functionSelectors[5] = LiquidityLogic.unpauseExecution.selector;

        functionSelectorRules[5] = SRPELib.Rules({
            ruleCount: 1,
            rules: new SRPELib.Rule[](1)
        });

            functionSelectorRules[5].rules[0] = SRPELib.Rule({
                ruleType: 5,
                ruleData: abi.encode(functionSelectors[5], allowedLender),
                extraData: ""
            });

        // initialize operator position
        functionSelectors[6] = LiquidityLogic.initializeOperatorPosition.selector;

        functionSelectorRules[6] = SRPELib.Rules({
            ruleCount: 1,
            rules: new SRPELib.Rule[](1)
        });

            functionSelectorRules[6].rules[0] = SRPELib.Rule({
                ruleType: 5,
                ruleData: abi.encode(functionSelectors[6], address(this)),
                extraData: ""
            });

        return (functionSelectorRules, functionSelectors);
    }

    event EnclaveCreated(uint256 indexed enclaveId, address indexed sendraExecutor);
    event OfferAccepted(uint256 indexed batchId, uint256 indexed enclaveId, address indexed operator, address indexed sendraExecutor);

    error MinUsdcPerTxCannotBeZero();
    error MaxUsdcPerTxCannotBeLessThanMinUsdcPerTx();
    error MaxUsdcPerTxCannotBeZero();
    error DeadlineCannotBeInThePast();

}