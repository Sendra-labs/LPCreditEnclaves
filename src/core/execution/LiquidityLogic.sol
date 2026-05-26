//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ILiquidityOrchestratorEvo } from "../../interfaces/iSendraCore/ILiquidityOrchestratorEvo.sol";
import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { UniswapLib } from "../../libs/uni.lib.sol";
import { EnclavesStorage } from "../storage/EnclavesStorage.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SendraLib } from "../../libs/Sendra.lib.sol";
import { ISendraStorage } from "../../interfaces/iSendraCore/ISendraStorage.sol";
import { AccountingManager } from "./AccountingManager.sol";
import { IUniswapV3PositionNFT } from "../../interfaces/iSendraCore/sendraUniExec/IUniswapV3PositionNFT.sol";


/*
This contract is the logic for the liquidity provision and withdrawal for Enclaves. IS THE IMPLEMENTATION for the SendraUniversalExecutors.
Deployment instructions:
1. Must be set as the LiquidityLogic in the AddressProvider
2. The immutable address of the addressProvider should be reviewed if there are other deployments of addressProvider
3. requires Uniswap Position Manager to be registered in the AddressProvider as "UniswapNFTPositionManager"

*/
contract LiquidityLogic {

    address public immutable addressProvider;

    constructor(address _addressProvider) {
        addressProvider = _addressProvider;
    }

    modifier onlyNotPaused() {
        if(EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage")).isPausedControl()) revert Paused();
        _;
    }

    modifier onlyNotDeposited() {
        if(EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage")).isDepositedControl()) revert Deposited();
        _;
    }

    function initializeOperatorPosition() public {
        EnclavesStorage enclaveStorage = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"));
        LPCE.Enclave memory enclave = enclaveStorage.getEnclaveByAddress(address(this));
        if(enclave.operatorPositionId > 0) revert OperatorPositionAlreadyInitialized();
        bytes[] memory positionData = new bytes[](7);
        positionData[0] = abi.encode(enclave.creditInUsd); // initial Credit under management
        positionData[1] = abi.encode(block.timestamp); // initial date
        positionData[2] = abi.encode(address(this)); // address of the enclave
        positionData[3] = abi.encode(enclave.operatorFee); // operator fee
        positionData[4] = abi.encode(0); // final Value
        positionData[5] = abi.encode(0); // final date
        positionData[6] = abi.encode(0); // Operator profit

        uint256 operatorPositionId = AccountingManager(ISendraAddressProvider(addressProvider).getAddress("AccountingManager")).initializePositionForUser(enclave.operator, positionData);
        enclaveStorage.setOperatorPositionId(operatorPositionId);
    }

    function provideLiquidity(
            uint256 usdcAmount,
            uint256 amount0,
            uint256 amount1,
            UniswapLib.Protocol protocol,
            int24 tickLower,
            int24 tickUpper,
            uint24 fee,
            address token0, 
            address token1,
            address user,
            UniswapLib.SwapInput swapInput0; 
            UniswapLib.SwapInput swapInput1;
        ) public onlyNotPaused {

            address liquidityOrchestrator = ISendraAddressProvider(addressProvider).getAddress("LiquidityOrchestratorEvo");
            
            IERC20(IAddressProvider(addressProvider).getAddress("USDC")).approve(liquidityOrchestrator, usdcAmount);
            
            ILiquidityOrchestratorEvo executor = ILiquidityOrchestratorEvo(liquidityOrchestrator);

            UniswapLib.ExecuteProvideLiquidityInput memory params = UniswapLib.ExecuteProvideLiquidityInput({
                swapInput0,
                swapInput1,
                UniswapLib.ProvideLiquidityInput({
                    protocol,
                    token0,
                    token1,
                    address(this),
                    user, // CHECK por que esto cambiará seguramente en el nuevo liquiOrches
                    amount0, 
                    amount1,
                    tickLower,
                    tickUpper,
                    fee
                }),
                false 
            }) 

            bytes[] memory positionData = executor.provideLiquidity(params);

            AccountingManager(ISendraAddressProvider(addressProvider).getAddress("AccountingManager")).initializePositionForEnclave(positionData);

    }

    function closePosition(uint256 positionId, UniswapLib.SwapInput swapInput0, UniswapLib.SwapInput swapInput1) public {

        SendraLib.Position memory position = AccountingManager(ISendraAddressProvider(addressProvider).getAddress("SendraStorage")).getUserPositionById(address(this), positionId);
        uint256 uniId = position.positionData[9];

        ILiquidityOrchestratorEvo executor = ILiquidityOrchestratorEvo(
            ISendraAddressProvider(addressProvider).getAddress("LiquidityOrchestratorEvo")
        );

        IUniswapV3PositionNFT(ISendraAddressProvider(addressProvider).getAddress("UniswapNFTPositionManager")).approve(address(executor), uniId);

        UniswapLib.ExecuteWithdrawLiquidityAndCollectFees params = UniswapLib.ExecuteWithdrawLiquidityAndCollectFees(
            UniswapLib.WithdrawLiquidityInput({
                uniId: uniId,
                positionId: positionId,
                user: address(this)
            }),
            swapInput0,
            swapInput1
        );

        (,SendraLib.Position memory position) = executor.withdrawLiquidityAndCollectFees(params);

        address managerAddress = ISendraAddressProvider(addressProvider).getAddress("AccountingManager");

        AccountingManager(managerAddress).manageFullPositionForEnclave(positionId, position);
        AccountingManager(managerAddress).decreaseGlobalPositionActivePositions(msg.sender);

    }

    function depositCredit(uint256 creditInUsd) public onlyNotDeposited {
        EnclavesStorage enclaveStorage = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"));
        enclaveStorage.setIsDeposited();
        IERC20(IAddressProvider(addressProvider).getAddress("USDC")).transferFrom(msg.sender, address(this), creditInUsd);

        bytes[] memory positionData = new bytes[](6);
        positionData[0] = abi.encode(creditInUsd);
        positionData[1] = abi.encode(address(this)); // address of the enclave
        positionData[2] = abi.encode(block.timestamp); // timestamp of the deposit
        positionData[3] = abi.encode(1); // chain id
        positionData[4] = abi.encode(0); // final Value
        positionData[5] = abi.encode(0); // final date

        uint256 lenderPositionId = AccountingManager(ISendraAddressProvider(addressProvider).getAddress("AccountingManager")).initializePositionForUser(msg.sender, positionData);

        enclaveStorage.setLenderPositionId(lenderPositionId);
        
        emit CreditDeposited(msg.sender, creditInUsd);
    }

    function withdrawCredit() public {

        SendraStorage sendraStorage = SendraStorage(ISendraAddressProvider(addressProvider).getAddress("SendraStorage"));

        SendraLib.UserInfoRead memory userInfo = sendraStorage.getUser(address(this));
        if(userInfo.activePositions > 0) revert PositionsNotClosed();

        EnclavesStorage enclaveStorage = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"));
        LPCE.Enclave memory enclave = enclaveStorage.getEnclaveByAddress(address(this));
        
        uint256 initialCredit = enclave.creditInUsd;
        
        uint256 currentValue = IERC20(IAddressProvider(addressProvider).getAddress("USDC")).balanceOf(address(this));
        uint256 operatorFee = enclave.operatorFee;
        uint256 profit = currentValue > initialCredit ? currentValue - initialCredit : 0;
        uint256 operatorProfit = profit * operatorFee / 100;
        uint256 lenderProfit = profit - operatorProfit;
        address operator = enclave.operator;
        address lender = enclave.lender;
        uint256 lenderPositionId = enclave.lenderPositionId;
        uint256 operatorPositionId = enclave.operatorPositionId;

        SendraLib.Position memory lenderPosition = sendraStorage.getUserPositionById(lender, lenderPositionId);
        SendraLib.Position memory operatorPosition = sendraStorage.getUserPositionById(operator, operatorPositionId);

        if(profit > 0) {
            IERC20(IAddressProvider(addressProvider).getAddress("USDC")).transfer(lender, lenderProfit + initialCredit);
            IERC20(IAddressProvider(addressProvider).getAddress("USDC")).transfer(operator, operatorProfit);
            lenderPosition.positionData[4] = abi.encode(lenderProfit + initialCredit);
            operatorPosition.positionData[XXX] = abi.encode(operatorProfit);
            lenderPosition.pnl = lenderProfit;
            operatorPosition.pnl = operatorProfit;
        } else {
            IERC20(IAddressProvider(addressProvider).getAddress("USDC")).transfer(creditor, currentValue);
            IERC20(IAddressProvider(addressProvider).getAddress("USDC")).transfer(operator, 0);
            lenderPosition.positionData[4] = abi.encode(currentValue);
            operatorPosition.positionData[XXX] = abi.encode(0);
            lenderPosition.pnl = initialCredit - currentValue;
            operatorPosition.pnl = 0;
        }

        lenderPosition.isActive = false;
        operatorPosition.isActive = false;

        AccountingManager(managerAddress).updateFullPositionForUser(lender, lenderPosition.id, lenderPosition);
        AccountingManager(managerAddress).updateFullPositionForUser(operator, operatorPosition.id, operatorPosition);

        AccountingManager(managerAddress).decreaseGlobalPositionActivePositions(lender);
        AccountingManager(managerAddress).decreaseGlobalPositionActivePositions(operator);

        enclaveStorage.removeEnclaveFromUser(lender, 0, enclave.enclaveId);
        enclaveStorage.removeEnclaveFromUser(operator, 1, enclave.enclaveId);

        emit CreditWithdrawn(lender, lenderProfit + initialCredit, operator, operatorProfit);

    }

    function pauseExecution() public {
        ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage").pauseExecution();
        emit ExecutionPaused();
    }

    function unpauseExecution() public {
        ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage").unpauseExecution();
        emit ExecutionUnpaused();
    }

    event CreditWithdrawn(address indexed lender, uint256 amount, address indexed operator, uint256 operatorProfit);
    event CreditDeposited(address indexed lender, uint256 amount);
    event ExecutionPaused();
    event ExecutionUnpaused();

    error Paused();
    error Deposited();
    error PositionsNotClosed();
    error OperatorPositionAlreadyInitialized();
}