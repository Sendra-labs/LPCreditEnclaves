//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { UniswapLib } from "../../libs/uni.lib.sol";
import { AccountLp, ISendraLpAccount } from "../../libs/AccountLp.sol";
import { EnclaveAccounts, IAccountsManager } from "../../libs/EnclaveAccounts.sol";
import { EnclavesStorage } from "../storage/EnclavesStorage.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SendraLib } from "../../libs/Sendra.lib.sol";
import { ISendraStorage } from "../../interfaces/iSendraCore/ISendraStorage.sol";
import { AccountingManager } from "./AccountingManager.sol";
import { LPCE } from "../../libs/LPCE.lib.sol";


/*
This contract is the logic for the liquidity provision and withdrawal for Enclaves. IS THE IMPLEMENTATION for the SendraUniversalExecutors.
Deployment instructions:
1. Must be set as the LiquidityLogic in the AddressProvider
2. The immutable address of the addressProvider should be reviewed if there are other deployments of addressProvider
3. requires Uniswap Position Manager to be registered in the AddressProvider as "UniswapNFTPositionManager"

*/
contract LiquidityLogic {
    using SafeERC20 for IERC20;

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

    /// @notice Opens Uniswap v3 or v4 through the enclave's Sendra account.
    ///         `usdcAmount` stays argument 0 so the enclave rule can cap it.
    ///         `token0`, `token1` and `fee` are static words the ruler can allowlist.
    ///         They must match the nested input, or the operator could show one pair and mint another.
    ///         The account pulls `usdcAmount`. v4 is `protocol` 2 plus `tickSpacing` and `hooks`.
    function provideLiquidity(
        uint256 usdcAmount,
        address token0,
        address token1,
        uint24 fee,
        AccountLp.ExecuteProvideLiquidityInput calldata input
    ) public onlyNotPaused returns (uint256 positionId) {
        _matchLp(token0, token1, fee, input);
        positionId = _provide(usdcAmount, input);
    }

    function provideLiquidityNoAccountingTest(
        uint256 usdcAmount,
        address token0,
        address token1,
        uint24 fee,
        AccountLp.ExecuteProvideLiquidityInput calldata input
    ) public onlyNotPaused returns (uint256 positionId) {
        _matchLp(token0, token1, fee, input);
        positionId = _provide(usdcAmount, input);
    }

    function partialClose(uint256 uniId, uint256 positionId) public {
        ISendraLpAccount(_lpAccount()).partialClose(AccountLp.PartialCloseInput({
            uniId: uniId,
            positionId: positionId,
            user: address(this)
        }));
    }

    function sellHeld(
        uint256 positionId,
        UniswapLib.SwapInput calldata swapInput0,
        UniswapLib.SwapInput calldata swapInput1
    ) public {
        ISendraLpAccount(_lpAccount()).sellHeld(AccountLp.SellHeldInput({
            positionId: positionId,
            user: address(this),
            swapInput0: swapInput0,
            swapInput1: swapInput1
        }));
    }

    function closePosition(uint256 positionId, UniswapLib.SwapInput calldata swapInput0, UniswapLib.SwapInput calldata swapInput1) public {
        ISendraStorage sendraStorage = ISendraStorage(ISendraAddressProvider(addressProvider).getAddress("SendraStorage"));
        SendraLib.Position memory position = sendraStorage.getUserPositionById(address(this), positionId);
        uint256 uniId = abi.decode(position.positionData[9], (uint256));

        ISendraLpAccount(_lpAccount()).withdraw(AccountLp.ExecuteWithdrawLiquidityAndCollectFees({
            withdrawInput: AccountLp.WithdrawInput({
                uniId: uniId,
                positionId: positionId,
                user: address(this)
            }),
            swapInput0: swapInput0,
            swapInput1: swapInput1
        }));
    }

    function _matchLp(
        address token0,
        address token1,
        uint24 fee,
        AccountLp.ExecuteProvideLiquidityInput calldata input
    ) internal pure {
        if (
            input.provideLiquidityInput.token0 != token0
                || input.provideLiquidityInput.token1 != token1
                || input.provideLiquidityInput.fee != fee
        ) revert AmountMismatch();
    }

    function _provide(uint256 usdcAmount, AccountLp.ExecuteProvideLiquidityInput calldata input)
        internal
        returns (uint256 positionId)
    {
        uint256 pull = input.swapInput0.amountIn0 + input.swapInput1.amountIn0;
        if (pull != usdcAmount) revert AmountMismatch();

        address account = EnclaveAccounts.spot(addressProvider);
        IERC20(ISendraAddressProvider(addressProvider).getAddress("USDC")).forceApprove(account, pull);

        AccountLp.ExecuteProvideLiquidityInput memory params = input;
        params.provideLiquidityInput.user = address(this);
        params.provideLiquidityInput.recipient = account;
        positionId = ISendraLpAccount(account).provide(params);
    }

    function _lpAccount() internal view returns (address account) {
        account = IAccountsManager(ISendraAddressProvider(addressProvider).getAddress("AccountsManager")).accountByOwner(address(this));
        if (account == address(0)) revert NoSpotAccount();
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
        uint256 lastActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(15, lender));

        uint8[] memory gFieldIds = new uint8[](5);
        int256[] memory gDeltas = new int256[](5);

        gFieldIds[0] = 0;
        gDeltas[0] = int256(creditInUsd);

        gFieldIds[1] = 2;
        gDeltas[1] = newExposure > peakExposure ? int256(newExposure - peakExposure) : int256(0);

        gFieldIds[2] = 3;
        gDeltas[2] = int256(creditInUsd);

        gFieldIds[3] = 9;
        gDeltas[3] = 1;

        gFieldIds[4] = 15;
        gDeltas[4] = int256(block.timestamp - lastActivityTimestamp);

        AccountingManager(accountingManager).applyGlobalPulseDeltas(
            lender,
            gFieldIds,
            gDeltas
        );

        AccountingManager(accountingManager).recordCapitalDeposit(creditInUsd);

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

        if(!lenderPosition.isActive) revert PositionNotActive();

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
            lenderPosition.pnl = int256(currentValue) - int256(creditInUsd);
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
        lenderGFieldIds[10] = 19;
        lenderGDeltas[6] = 1;

        if(lenderPnl > 0) {
            lenderGFieldIds[3] = 5;
            lenderGDeltas[3] = lenderPnl;
            lenderGDeltas[4] = highWaterMark < newPnl ? newPnl - highWaterMark : int256(0);
            lenderGDeltas[5] = 0;
            lenderGFieldIds[7] = 11;
            lenderGDeltas[7] = 1;
            lenderGDeltas[10] = int256(0);
        } else {
            lenderGFieldIds[3] = 6;
            lenderGDeltas[3] = lenderPnl < 0 ? -lenderPnl : int256(0);
            lenderGDeltas[4] = 0;
            int256 drawdown = (newPnl < highWaterMark) ? highWaterMark - newPnl : int256(0);
            lenderGDeltas[5] = maxDrawdown < drawdown ? drawdown - maxDrawdown : int256(0);
            lenderGFieldIds[7] = 12;
            lenderGDeltas[7] = lenderPnl < 0 ? int256(1) : int256(0);
            lenderGDeltas[10] = lenderPnl < 0 ? int256(creditInUsd) : int256(0);
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

        manager.recordCapitalWithdrawal(creditInUsd);

        emit CreditWithdrawn(lender, capitalOutToLender, operator, operatorProfit);
    }

    function buySpot(uint256 usdcAmount, address tokenOut, UniswapLib.SwapInput calldata input) external onlyNotPaused {
        if (input.tokenOut != tokenOut) revert AmountMismatch();
        usdcAmount;
        _desk();
    }

    function sellSpot(UniswapLib.SwapInput calldata input) external {
        input;
        _desk();
    }

    function openSupply(address asset, uint256 usdcAmount, UniswapLib.SwapInput calldata swap) external onlyNotPaused {
        asset;
        usdcAmount;
        swap;
        _desk();
    }

    function openLoop(
        address asset,
        uint256 usdcAmount,
        uint8 loops,
        uint16 borrowBps,
        UniswapLib.SwapInput calldata swap
    ) external onlyNotPaused {
        asset;
        usdcAmount;
        loops;
        borrowBps;
        swap;
        _desk();
    }

    function openShort(
        address asset,
        uint256 usdcAmount,
        uint8 loops,
        uint16 borrowBps,
        bool releaseToOwner,
        UniswapLib.SwapInput calldata sellAsset
    ) external onlyNotPaused {
        asset;
        usdcAmount;
        loops;
        borrowBps;
        releaseToOwner;
        sellAsset;
        _desk();
    }

    function openLeveraged(
        address asset,
        uint256 usdcAmount,
        uint16 borrowBps,
        UniswapLib.SwapInput calldata buyAsset,
        bool collateralIsAsset,
        bytes calldata lpData
    ) external onlyNotPaused {
        asset;
        usdcAmount;
        borrowBps;
        buyAsset;
        collateralIsAsset;
        lpData;
        _desk();
    }

    function openBasket(
        address collateral,
        uint256 usdcAmount,
        UniswapLib.SwapInput calldata buyCollateral,
        UniswapLib.BasketBuy[] calldata buys
    ) external onlyNotPaused {
        collateral;
        usdcAmount;
        buyCollateral;
        buys;
        _desk();
    }

    function closeStrategy(
        address account,
        uint256 positionId,
        uint256 fundAmount,
        UniswapLib.SwapInput calldata swap
    ) external {
        account;
        positionId;
        fundAmount;
        swap;
        _desk();
    }

    function releaseShort(address account, uint256 positionId) external {
        account;
        positionId;
        _desk();
    }

    function closeLeveraged(
        address account,
        uint256 positionId,
        uint256 fundAmount,
        uint256 uniId,
        uint256 lpPositionId,
        bytes calldata exitData
    ) external {
        account;
        positionId;
        fundAmount;
        uniId;
        lpPositionId;
        exitData;
        _desk();
    }

    /// @dev Second delegatecall. msg.data is still the LiquidityLogic selector,
    ///      and address(this) is still the enclave executor.
    function _desk() internal {
        address desk = ISendraAddressProvider(addressProvider).getAddress("EnclaveDesk");
        (bool ok, bytes memory reason) = desk.delegatecall(msg.data);
        if (!ok) {
            assembly {
                revert(add(reason, 32), mload(reason))
            }
        }
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
    error PositionNotActive();
    error AmountMismatch();
    error NoSpotAccount();
}