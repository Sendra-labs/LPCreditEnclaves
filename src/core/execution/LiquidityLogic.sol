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
import { LPCE } from "../../libs/LPCE.lib.sol";


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
            UniswapLib.SwapInput calldata swapInput0,
            UniswapLib.SwapInput calldata swapInput1
        ) public onlyNotPaused {

            address liquidityOrchestrator = ISendraAddressProvider(addressProvider).getAddress("LiquidityOrchestratorEvo");
            
            IERC20(ISendraAddressProvider(addressProvider).getAddress("USDC")).approve(liquidityOrchestrator, usdcAmount);
            
            ILiquidityOrchestratorEvo executor = ILiquidityOrchestratorEvo(liquidityOrchestrator);

            UniswapLib.ExecuteProvideLiquidityInput memory params = UniswapLib.ExecuteProvideLiquidityInput({
                swapInput0: swapInput0,
                swapInput1: swapInput1,
                provideLiquidityInput: UniswapLib.ProvideLiquidityInput({
                    protocol: protocol,
                    token0: token0,
                    token1: token1,
                    recipient: address(this),
                    user: msg.sender,
                    amount0: amount0,
                    amount1: amount1,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    fee: fee
                }),
                isSendraRecipient: false
            });

            (bytes[] memory positionData, uint8[] memory gFieldIdsProvider, int256[] memory gDeltasProvider) =
                executor.provideLiquidity(params);

            address accountingManager = ISendraAddressProvider(addressProvider).getAddress("AccountingManager");
            AccountingManager(accountingManager).initializePositionForEnclave(positionData);
            AccountingManager(accountingManager).applyGlobalPulseDeltas(msg.sender, gFieldIdsProvider, gDeltasProvider);

    }

    function closePosition(uint256 positionId, UniswapLib.SwapInput calldata swapInput0, UniswapLib.SwapInput calldata swapInput1) public {
        ISendraStorage sendraStorage = ISendraStorage(ISendraAddressProvider(addressProvider).getAddress("SendraStorage"));
        SendraLib.Position memory position = sendraStorage.getUserPositionById(address(this), positionId);
        uint128 uniId = abi.decode(position.positionData[9], (uint128));

        LPCE.Enclave memory enclave = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"))
            .getEnclaveByAddress(address(this));
        address lender = enclave.lender;
        address operator = enclave.operator;

        ILiquidityOrchestratorEvo executor = ILiquidityOrchestratorEvo(
            ISendraAddressProvider(addressProvider).getAddress("LiquidityOrchestratorEvo")
        );

        IUniswapV3PositionNFT(ISendraAddressProvider(addressProvider).getAddress("UniswapNFTPositionManager")).approve(address(executor), uniId);

        UniswapLib.ExecuteWithdrawLiquidityAndCollectFees memory params = UniswapLib.ExecuteWithdrawLiquidityAndCollectFees({
            withdrawLiquidityInput: UniswapLib.WithdrawLiquidityInput({
                uniId: uniId,
                positionId: positionId,
                user: address(this)
            }),
            operator: operator,
            swapInput0: swapInput0,
            swapInput1: swapInput1
        });

        SendraLib.Position memory closedPosition;
        uint8[] memory gFieldIdsProvider;
        int256[] memory gDeltasProvider;

        if (msg.sender == lender) {
            (, closedPosition, gFieldIdsProvider, gDeltasProvider) =
                executor.withdrawLiquidityAndCollectFeesFromLender(params);
        } else {
            (, closedPosition, gFieldIdsProvider, gDeltasProvider) =
                executor.withdrawLiquidityAndCollectFees(params);
        }

        address managerAddress = ISendraAddressProvider(addressProvider).getAddress("AccountingManager");
        AccountingManager manager = AccountingManager(managerAddress);

        manager.manageFullPositionForEnclave(positionId, closedPosition);
        manager.applyGlobalPulseDeltas(operator, gFieldIdsProvider, gDeltasProvider);
        manager.decreaseGlobalPositionActivePositions(address(this));
    }

    function revokeEnclave() public onlyNotDeposited {
        EnclavesStorage enclaveStorage = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"));
        LPCE.Enclave memory enclave = enclaveStorage.getEnclaveByAddress(address(this));

        ISendraStorage sendraStorage = ISendraStorage(ISendraAddressProvider(addressProvider).getAddress("SendraStorage"));
        if(sendraStorage.getUser(address(this)).activePositions > 0) revert OpenEnclavePositionsNotClosed();

        address managerAddress = ISendraAddressProvider(addressProvider).getAddress("AccountingManager");
        AccountingManager manager = AccountingManager(managerAddress);

        if(enclave.operatorPositionId > 0) {
            SendraLib.Position memory operatorPosition = sendraStorage.getUserPositionById(
                enclave.operator,
                enclave.operatorPositionId
            );
            if(operatorPosition.isActive) {
                operatorPosition.isActive = false;
                operatorPosition.positionData[5] = abi.encode(block.timestamp);
                manager.updateFullPositionForUser(enclave.operator, operatorPosition.id, operatorPosition);
                manager.decreaseGlobalPositionActivePositions(enclave.operator);
            }
        }

        manager.revokeEnclaveListing();

        emit EnclaveRevoked(enclave.lender, enclave.operator);
    }

    function depositCredit(uint256 creditInUsd) public onlyNotDeposited {
        EnclavesStorage enclaveStorage = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"));
        enclaveStorage.setIsDeposited();
        IERC20(ISendraAddressProvider(addressProvider).getAddress("USDC")).transferFrom(msg.sender, address(this), creditInUsd);

        bytes[] memory positionData = new bytes[](6);
        positionData[0] = abi.encode(creditInUsd);
        positionData[1] = abi.encode(address(this)); // address of the enclave
        positionData[2] = abi.encode(block.timestamp); // timestamp of the deposit
        positionData[3] = abi.encode(100); // chain id
        positionData[4] = abi.encode(0); // final Value
        positionData[5] = abi.encode(0); // final date

        address accountingManager = ISendraAddressProvider(addressProvider).getAddress("AccountingManager");

        uint256 lenderPositionId = AccountingManager(accountingManager).initializePositionForUser(msg.sender, positionData);

        enclaveStorage.setLenderPositionId(lenderPositionId);

        address lender = msg.sender;
        ISendraStorage sendraStorage = ISendraStorage(ISendraAddressProvider(addressProvider).getAddress("SendraStorage"));

        uint256 peakExposure = uint256(sendraStorage.getUniqueGlobalAccumulator(2, lender));
        uint256 currentExposure = uint256(sendraStorage.getUniqueGlobalAccumulator(3, lender));
        uint256 newExposure = currentExposure + creditInUsd;
        uint256 firstActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(14, lender));
        uint256 lastActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(15, lender));

        uint8[] memory gFieldIds = new uint8[](6);
        int256[] memory gDeltas = new int256[](6);

        gFieldIds[0] = 0;
        gDeltas[0] = int256(creditInUsd);

        gFieldIds[1] = 2;
        gDeltas[1] = newExposure > peakExposure ? int256(newExposure - peakExposure) : int256(0);

        gFieldIds[2] = 3;
        gDeltas[2] = int256(creditInUsd);

        gFieldIds[3] = 9;
        gDeltas[3] = 1;

        gFieldIds[4] = 14;
        gDeltas[4] = firstActivityTimestamp == 0 ? int256(block.timestamp) : int256(0);

        gFieldIds[5] = 15;
        gDeltas[5] = int256(block.timestamp - lastActivityTimestamp);

        AccountingManager(accountingManager).applyGlobalPulseDeltas(
            lender,
            gFieldIds,
            gDeltas
        );

        emit CreditDeposited(lender, creditInUsd);
    }

    function withdrawCredit() public {
        address storageAddress = ISendraAddressProvider(addressProvider).getAddress("SendraStorage");
        ISendraStorage sendraStorage = ISendraStorage(storageAddress);

        SendraLib.UserInfoRead memory userInfo = sendraStorage.getUser(address(this));
        if(userInfo.activePositions > 0) revert PositionsNotClosed();

        EnclavesStorage enclaveStorage = EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage"));
        LPCE.Enclave memory enclave = enclaveStorage.getEnclaveByAddress(address(this));

        address operator = enclave.operator;
        address lender = enclave.lender;
        uint256 lenderPositionId = enclave.lenderPositionId;
        uint256 operatorPositionId = enclave.operatorPositionId;

        SendraLib.Position memory lenderPosition = sendraStorage.getUserPositionById(lender, lenderPositionId);
        SendraLib.Position memory operatorPosition = sendraStorage.getUserPositionById(operator, operatorPositionId);

        // Accounting position is source of truth for pulse (must match depositCredit deltas).
        uint256 creditInUsd = abi.decode(lenderPosition.positionData[0], (uint256));
        uint256 openTimestamp = abi.decode(lenderPosition.positionData[2], (uint256));

        uint256 currentValue = IERC20(ISendraAddressProvider(addressProvider).getAddress("USDC")).balanceOf(address(this));
        uint256 operatorFee = enclave.operatorFee;
        uint256 profit = currentValue > creditInUsd ? currentValue - creditInUsd : 0;
        uint256 operatorProfit = profit * operatorFee / 100;
        uint256 lenderProfit = profit - operatorProfit;

        uint256 capitalOutToLender;

        if(profit > 0) {
            capitalOutToLender = lenderProfit + creditInUsd;
            IERC20(ISendraAddressProvider(addressProvider).getAddress("USDC")).transfer(lender, capitalOutToLender);
            IERC20(ISendraAddressProvider(addressProvider).getAddress("USDC")).transfer(operator, operatorProfit);
            lenderPosition.positionData[4] = abi.encode(capitalOutToLender);
            operatorPosition.positionData[6] = abi.encode(operatorProfit);
            lenderPosition.pnl = int256(lenderProfit);
            operatorPosition.pnl = int256(operatorProfit);
        } else {
            capitalOutToLender = currentValue;
            IERC20(ISendraAddressProvider(addressProvider).getAddress("USDC")).transfer(lender, capitalOutToLender);
            IERC20(ISendraAddressProvider(addressProvider).getAddress("USDC")).transfer(operator, 0);
            lenderPosition.positionData[4] = abi.encode(capitalOutToLender);
            operatorPosition.positionData[6] = abi.encode(0);
            lenderPosition.pnl = int256(creditInUsd) - int256(currentValue);
            operatorPosition.pnl = 0;
        }

        int256 lenderPnl = lenderPosition.pnl;

        int256 highWaterMark = sendraStorage.getUniqueGlobalAccumulator(7, lender);
        int256 currentPnl = sendraStorage.getUniqueGlobalAccumulator(4, lender);
        int256 newPnl = currentPnl + lenderPnl;
        int256 maxDrawdown = sendraStorage.getUniqueGlobalAccumulator(8, lender);
        uint256 lastActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(15, lender));

        uint8[] memory lenderGFieldIds = new uint8[](11);
        int256[] memory lenderGDeltas = new int256[](11);

        lenderGFieldIds[0] = 1;
        lenderGDeltas[0] = int256(capitalOutToLender);

        lenderGFieldIds[1] = 3;
        lenderGDeltas[1] = -int256(creditInUsd);

        lenderGFieldIds[2] = 4;
        lenderGDeltas[2] = lenderPnl;

        lenderGFieldIds[4] = 7;
        lenderGFieldIds[5] = 8;
        lenderGFieldIds[6] = 10;
        lenderGFieldIds[7] = 19;
        lenderGDeltas[6] = 1;

        if(lenderPnl > 0) {
            lenderGFieldIds[3] = 5;
            lenderGDeltas[3] = lenderPnl;
            lenderGDeltas[4] = highWaterMark < newPnl ? newPnl - highWaterMark : int256(0);
            lenderGDeltas[5] = 0;
            lenderGFieldIds[7] = 11;
            lenderGDeltas[7] = 1;
            lenderGDeltas[8] = int256(0);
        } else {
            lenderGFieldIds[3] = 6;
            lenderGDeltas[3] = lenderPnl < 0 ? -lenderPnl : int256(0);
            lenderGDeltas[4] = 0;
            int256 drawdown = (newPnl < highWaterMark) ? highWaterMark - newPnl : int256(0);
            lenderGDeltas[5] = maxDrawdown < drawdown ? drawdown - maxDrawdown : int256(0);
            lenderGFieldIds[7] = 12;
            lenderGDeltas[7] = lenderPnl < 0 ? int256(1) : int256(0);
            lenderGDeltas[8] = int256(abi.decode(lenderPosition.positionData[15], (uint256)));
        }

        lenderGFieldIds[8] = 13;
        lenderGDeltas[8] = int256(block.timestamp - openTimestamp);

        lenderGFieldIds[9] = 15;
        lenderGDeltas[9] = int256(block.timestamp - lastActivityTimestamp);

        address managerAddress = ISendraAddressProvider(addressProvider).getAddress("AccountingManager");
        AccountingManager manager = AccountingManager(managerAddress);
        manager.applyGlobalPulseDeltas(lender, lenderGFieldIds, lenderGDeltas);

        int256 operatorPnl = operatorPosition.pnl;
        int256 operatorHighWaterMark = sendraStorage.getUniqueGlobalAccumulator(7, operator);
        int256 operatorCurrentPnl = sendraStorage.getUniqueGlobalAccumulator(4, operator);
        int256 operatorNewPnl = operatorCurrentPnl + operatorPnl;
        uint256 operatorLastActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(15, operator));

        uint8 operatorPulseLen = operatorPnl > 0 ? 4 : 2;
        uint8[] memory operatorGFieldIds = new uint8[](operatorPulseLen);
        int256[] memory operatorGDeltas = new int256[](operatorPulseLen);

        operatorGFieldIds[0] = 4;
        operatorGDeltas[0] = operatorPnl;

        if(operatorPnl > 0) {
            operatorGFieldIds[1] = 5;
            operatorGDeltas[1] = operatorPnl;
            operatorGFieldIds[2] = 7;
            operatorGDeltas[2] = operatorHighWaterMark < operatorNewPnl ? operatorNewPnl - operatorHighWaterMark : int256(0);
            operatorGFieldIds[3] = 15;
            operatorGDeltas[3] = int256(block.timestamp - operatorLastActivityTimestamp);
        } else {
            operatorGFieldIds[1] = 15;
            operatorGDeltas[1] = int256(block.timestamp - operatorLastActivityTimestamp);
        }

        manager.applyGlobalPulseDeltas(operator, operatorGFieldIds, operatorGDeltas);

        lenderPosition.isActive = false;
        operatorPosition.isActive = false;

        lenderPosition.positionData[5] = abi.encode(block.timestamp);
        operatorPosition.positionData[5] = abi.encode(block.timestamp);
        operatorPosition.positionData[4] = abi.encode(currentValue);

        manager.updateFullPositionForUser(lender, lenderPosition.id, lenderPosition);
        manager.updateFullPositionForUser(operator, operatorPosition.id, operatorPosition);

        manager.decreaseGlobalPositionActivePositions(lender);
        manager.decreaseGlobalPositionActivePositions(operator);

        uint256 enclaveId = enclaveStorage.getEnclaveId(address(this));

        manager.removeEnclaveFromUser(lender, 0, enclaveId);
        manager.removeEnclaveFromUser(operator, 1, enclaveId);

        emit CreditWithdrawn(lender, capitalOutToLender, operator, operatorProfit);
    }

    function pauseExecution() public {
        EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage")).pauseExecution();
        emit ExecutionPaused();
    }

    function unpauseExecution() public {
        EnclavesStorage(ISendraAddressProvider(addressProvider).getAddress("EnclavesStorage")).unpauseExecution();
        emit ExecutionUnpaused();
    }

    event CreditWithdrawn(address indexed lender, uint256 amount, address indexed operator, uint256 operatorProfit);
    event CreditDeposited(address indexed lender, uint256 amount);
    event EnclaveRevoked(address indexed lender, address indexed operator);
    event ExecutionPaused();
    event ExecutionUnpaused();

    error Paused();
    error Deposited();
    error PositionsNotClosed();
    error OpenEnclavePositionsNotClosed();
    error OperatorPositionAlreadyInitialized();
}