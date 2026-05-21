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

        SRPELib.Rules memory functionSelectorRules;
        bytes4[] memory functionSelectors;

        (functionSelectorRules, functionSelectors) = createRules(
            params.creditInUsd, 
            params.minUsdcPerTx, 
            params.maxUsdcPerTx, 
            params.deadline, 
            params.operatorFee, 
            params.allowedOperator, 
            params.allowedTokens
        );

        SRPELib.NewRPFPInputs memory deployParams;
        deployParams._type = 1;
        deployParams.implementation = address(IAddressProvider(addressProvider).getAddress("LiquidityLogic"));
        deployParams.functionSelectorRules = functionSelectorRules;
        deployParams.functionSelectors = functionSelectors;

        /*address sendraExecutor = */ RPFPDeployer(addressProvider.getAddress("RPFPDeployer")).deployRPFP(deployParams); // MUST RETURN ADDRESS OF THE EXECUTOR

        LPCE.Enclave memory enclave = LPCE.Enclave({
            operator: params.allowedOperator,
            lender: msg.sender,
            sendraExecutor: /* sendraExecutor  */,
            isPaused: false,
            isDeposited: false,
            creditInUsd: params.creditInUsd,
            operatorFee: params.operatorFee,
            description: params.description
        });

        EnclavesStorage(addressProvider.getAddress("EnclavesStorage")).createEnclave(enclave);

        AccessControlInter(addressProvider.getAddress("AccessControlInter")).setIsSendraEnclave(sendraExecutor, true);

        emit EnclaveCreated(enclaveId, sendraExecutor);

        return (enclaveId, sendraExecutor);

    }

    function createRules(
            uint256 creditInUsd,
            uint256 minUsdcPerTx, 
            uint256 maxUsdcPerTx, 
            uint256 deadline, 
            uint256 operatorFee, 
            address allowedOperator,
            address[] memory allowedTokens
        ) internal view returns (SRPELib.Rules memory rules, bytes4[] memory functionSelectors) {
        
        if(minUsdcPerTx == 0) revert MinUsdcPerTxCannotBeZero();
        if(maxUsdcPerTx < minUsdcPerTx) revert MaxUsdcPerTxCannotBeLessThanMinUsdcPerTx();
        if(maxUsdcPerTx == 0) revert MaxUsdcPerTxCannotBeZero();
        if(deadline <= block.timestamp) revert DeadlineCannotBeInThePast();

        rules = SRPELib.Rules(
            {
                ruleCount: 8,
                rules: new SRPELib.Rule[](8)
            }
        );

        functionSelectors = new bytes4[](8);

        // Provide Liquidity
        functionSelectors[0] = LiquidityLogic.provideLiquidity.selector;

        rules.rules[0] = SRPELib.Rule({
            ruleType: 8,
            ruleData: abi.encode(minUsdcPerTx, maxUsdcPerTx),
            extraData: abi.encode(uint256(0)) // paramIndex of the usdc amount
        });
 
        // Time limit
        functionSelectors[1] = LiquidityLogic.provideLiquidity.selector;

        rules.rules[1] = SRPELib.Rule({
            ruleType: 3,
            ruleData: abi.encode(deadline, uint256(0)), 
            extraData: ""
        });


        // Allow specific operator
        functionSelectors[2] = LiquidityLogic.provideLiquidity.selector;

        rules.rules[2] = SRPELib.Rule({
            ruleType: 5,
            ruleData: abi.encode(functionSelectors[2], allowedOperator),
            extraData: ""
        });

        address[] memory allowedSenders = new address[](2);
        allowedSenders[0] = msg.sender;
        allowedSenders[1] = allowedOperator;

        // Withdraw Credit can be signed by the operator or the lender and logic sends the capital between both.
        functionSelectors[3] = LiquidityLogic.withdrawCredit.selector;

        rules.rules[3] = SRPELib.Rule({
            ruleType: 1,
            ruleData: abi.encode(allowedSenders),
            extraData: ""
        });

        functionSelectors[4] = LiquidityLogic.closePosition.selector; 

        rules.rules[4] = SRPELib.Rule({
            ruleType: 1,
            ruleData: abi.encode(allowedSenders),
            extraData: ""
        });

        functionSelectors[5] = LiquidityLogic.depositCredit.selector;

        rules.rules[5] = SRPELib.Rule({
            ruleType: 6,
            ruleData: abi.encode(functionSelectors[5], msg.sender, uint256(0), abi.encode(creditInUsd)), // paramIndex of the creditInUsd
            extraData: ""
        });

        // Only Lender can pause operations
        functionSelectors[6] = LiquidityLogic.pauseExecution.selector;

        rules.rules[6] = SRPELib.Rule({
            ruleType: 5,
            ruleData: abi.encode(functionSelectors[6], msg.sender),
            extraData: ""
        });

        functionSelectors[7] = LiquidityLogic.unpauseExecution.selector;

        rules.rules[7] = SRPELib.Rule({
            ruleType: 5,
            ruleData: abi.encode(functionSelectors[7], msg.sender),
            extraData: ""
        });

        // each new rule must add 1 to the functionSelectors length and rules.ruleCount

        return (rules, functionSelectors);

    }

    event EnclaveCreated(uint256 indexed enclaveId, address indexed sendraExecutor);

    error MinUsdcPerTxCannotBeZero();
    error MaxUsdcPerTxCannotBeLessThanMinUsdcPerTx();
    error MaxUsdcPerTxCannotBeZero();
    error DeadlineCannotBeInThePast();
}