/*
________________________________________________________________

  █████████                          █████                    
 ███▒▒▒▒▒███                        ▒▒███                     
▒███    ▒▒▒   ██████  ████████    ███████  ████████   ██████  
▒▒█████████  ███▒▒███▒▒███▒▒███  ███▒▒███ ▒▒███▒▒███ ▒▒▒▒▒███ 
 ▒▒▒▒▒▒▒▒███▒███████  ▒███ ▒███ ▒███ ▒███  ▒███ ▒▒▒   ███████ 
 ███    ▒███▒███▒▒▒   ▒███ ▒███ ▒███ ▒███  ▒███      ███▒▒███ 
▒▒█████████ ▒▒██████  ████ █████▒▒████████ █████    ▒▒████████
 ▒▒▒▒▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒▒▒ ▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒      ▒▒▒▒▒▒▒▒                                        
                                                              
 █████                 █████                                  
▒▒███                 ▒▒███                                   
 ▒███         ██████   ▒███████   █████                       
 ▒███        ▒▒▒▒▒███  ▒███▒▒███ ███▒▒                        
 ▒███         ███████  ▒███ ▒███▒▒█████                       
 ▒███      █ ███▒▒███  ▒███ ▒███ ▒▒▒▒███                      
 ███████████▒▒████████ ████████  ██████                       
▒▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒ ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒    Liquidity Orchestrator Evo                                                                                                                              
________________________________________________________________
*/

//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { ILiquidityManager } from "../../interfaces/iSendraCore/sendraUniExec/ILiquidityManager.sol";
import { ISwapRouter } from "../../interfaces/iSendraCore/sendraUniExec/ISwapRouter.sol";
import { UniswapLib } from "../../libs/uni.lib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IUniswapV3PositionNFT } from "../../interfaces/iSendraCore/sendraUniExec/IUniswapV3PositionNFT.sol";
import { ISendraAddressProvider } from "../../interfaces/iSendraCore/ISendraAddressProvider.sol";
import { ISendraStorage } from "../../interfaces/iSendraCore/ISendraStorage.sol";
import { SendraLib } from "../../libs/Sendra.lib.sol";

contract LiquidityOrchestratorEvo {
    using SafeERC20 for IERC20;

    ISendraAddressProvider public immutable addressProvider;
    ILiquidityManager public immutable liquidityManager;
    ISwapRouter public immutable swapRouter;
    IUniswapV3PositionNFT public immutable positionManager;
    ISendraStorage public immutable sendraStorage;

    constructor(address _addressProvider) {
        addressProvider = ISendraAddressProvider(_addressProvider);
        liquidityManager = ILiquidityManager(addressProvider.getAddress("LiquidityManager"));
        swapRouter = ISwapRouter(addressProvider.getAddress("SwapRouter"));
        positionManager = IUniswapV3PositionNFT(addressProvider.getAddress("UniswapNFTPositionManager"));
        sendraStorage = ISendraStorage(addressProvider.getAddress("SendraStorage"));
    }

    function provideLiquidity(UniswapLib.ExecuteProvideLiquidityInput calldata _input)
        public
        returns (bytes[] memory positionData, uint8[] memory gFieldIdsProvider, int256[] memory gDeltasProvider)
    {
        UniswapLib.SwapInput memory swapInput0 = _input.swapInput0;
        UniswapLib.SwapInput memory swapInput1 = _input.swapInput1;
        UniswapLib.ProvideLiquidityInput memory provideLiquidityInput = _input.provideLiquidityInput;
        address operator = provideLiquidityInput.user;

        gFieldIdsProvider = new uint8[](3);
        gDeltasProvider = new int256[](3);

        positionData = new bytes[](18);

        if(provideLiquidityInput.protocol == UniswapLib.Protocol.UniswapV3){
            
            bool isSwapNeeded0 = swapInput0.tokenIn != swapInput0.tokenOut;
            bool isSwapNeeded1 = swapInput1.tokenIn != swapInput1.tokenOut;

            IERC20(swapInput0.tokenIn).safeTransferFrom(
                msg.sender,
                isSwapNeeded0 ? address(swapRouter) : address(liquidityManager),
                swapInput0.amountIn0
            );

            IERC20(swapInput1.tokenIn).safeTransferFrom(
                msg.sender,
                isSwapNeeded1 ? address(swapRouter) : address(liquidityManager),
                swapInput1.amountIn0
            );

            uint256 totalUsdcAmountInput = swapInput0.amountIn0 + swapInput1.amountIn0;
            
            swapInput0.to = address(liquidityManager);
            swapInput1.to = address(liquidityManager);

            if(isSwapNeeded0) swapRouter.executeSwap(swapInput0);
            if(isSwapNeeded1) swapRouter.executeSwap(swapInput1);

            provideLiquidityInput.recipient = msg.sender;

            (
                uint256 tokenId, 
                uint256 amountDeposited0, 
                uint256 amountDeposited1, 
                uint160 sqrtCurrentPrice, 
                address pool,
                uint256 amountLeftToken0,
                uint256 amountLeftToken1
            ) = liquidityManager.addLiquidityV3(provideLiquidityInput);

            address baseToken = swapInput0.tokenIn;
            uint256 prevBaseBalance = IERC20(baseToken).balanceOf(address(this));
            uint256 leftUsdcDirect = 0;

            // swapInput0/swapInput1 are not guaranteed to be aligned with token0/token1.
            // Map by tokenOut so we invert the correct route for each leftover.
            UniswapLib.SwapInput memory swapIntoToken0 =
                (swapInput0.tokenOut == provideLiquidityInput.token0) ? swapInput0 : swapInput1;
            UniswapLib.SwapInput memory swapIntoToken1 =
                (swapInput0.tokenOut == provideLiquidityInput.token1) ? swapInput0 : swapInput1;

            if (amountLeftToken0 > 0) {
                // If leftover is already in base token (USDC), don't swap it back.
                if (provideLiquidityInput.token0 == baseToken) {
                    leftUsdcDirect += amountLeftToken0;
                } else {
                    IERC20(provideLiquidityInput.token0).safeTransfer(address(swapRouter), amountLeftToken0);
                    swapRouter.executeSwap(invertSwapInput(swapIntoToken0, amountLeftToken0));
                }
            }
            if (amountLeftToken1 > 0) {
                if (provideLiquidityInput.token1 == baseToken) {
                    leftUsdcDirect += amountLeftToken1;
                } else {
                    IERC20(provideLiquidityInput.token1).safeTransfer(address(swapRouter), amountLeftToken1);
                    swapRouter.executeSwap(invertSwapInput(swapIntoToken1, amountLeftToken1));
                }
            }

            uint256 baseAfter = IERC20(baseToken).balanceOf(address(this));
            uint256 leftUsdc = leftUsdcDirect + (baseAfter - prevBaseBalance);

            uint256 initialPositionUsdcValue = totalUsdcAmountInput - leftUsdc;

            IERC20(baseToken).safeTransfer(msg.sender, leftUsdc);

            positionData[0] = abi.encode(_input.provideLiquidityInput.token0);
            positionData[1] = abi.encode(_input.provideLiquidityInput.token1);
            positionData[2] = abi.encode(block.timestamp);
            positionData[3] = abi.encode(_input.provideLiquidityInput.fee);
            positionData[4] = abi.encode(_input.provideLiquidityInput.tickLower);
            positionData[5] = abi.encode(_input.provideLiquidityInput.tickUpper);
            positionData[6] = abi.encode(amountDeposited0);
            positionData[7] = abi.encode(amountDeposited1);
            positionData[8] = abi.encode(provideLiquidityInput.recipient);
            positionData[9] = abi.encode(tokenId);
            positionData[10] = abi.encode(sqrtCurrentPrice);
            positionData[11] = abi.encode(pool);
            positionData[12] = abi.encode(uint256(0)); // finalUsdValue
            positionData[13] = abi.encode(uint256(0)); // finalPoolPrice
            positionData[14] = abi.encode(uint256(0)); // feesCollectedUSD
            positionData[15] = abi.encode(initialPositionUsdcValue);
            positionData[16] = abi.encode(0); // final date
            positionData[17] = abi.encode(100); // chainId

            // [0] = token0
            // [1] = token1
            // [2] = openDate
            // [3] = fee
            // [4] = tickLower
            // [5] = tickUpper
            // [6] = amountDeposited0 token0
            // [7] = amountDeposited1 token1
            // [8] = recipient
            // [9] = tokenId
            // [10] = initial pool price
            // [11] = pool
            // [12] = finalUsdValue
            // [13] = finalPoolPrice
            // [14] = feesCollectedUSD
            // [15] = initialPositionUsdcValue
            // [16] = final date
            // [17] = chainId

            uint256 firstActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(14, operator));
            uint256 lastActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(15, operator));

            gFieldIdsProvider[0] = 9;
            gDeltasProvider[0] = 1;

            gFieldIdsProvider[1] = 14;
            gDeltasProvider[1] = firstActivityTimestamp == 0 ? int256(block.timestamp) : int256(0);

            gFieldIdsProvider[2] = 15;
            gDeltasProvider[2] = int256(block.timestamp - lastActivityTimestamp);

        } else if(provideLiquidityInput.protocol == UniswapLib.Protocol.UniswapV4){
            //TODO: Implement UniswapV4
        }

        return (positionData, gFieldIdsProvider, gDeltasProvider);
    }

    function updateAccumulators(address _user, uint8[] memory _gFieldIds, int256[] memory _gDeltas, uint64 _specificKey, uint8[] memory _sFieldIds, int256[] memory _sDeltas) internal {
        sendraStorage.applyGlobalPulseDeltas(_user, _gFieldIds, _gDeltas);
        sendraStorage.applySpecificPulseDeltas(_user, _specificKey, _sFieldIds, _sDeltas);
    }

    function invertSwapInput(UniswapLib.SwapInput memory _input, uint256 _amount)
        public
        view
        returns (UniswapLib.SwapInput memory)
    {
        uint256 len = _input.swapInstructions.length;

        UniswapLib.SwapInstruction[] memory invertedInstructions = new UniswapLib.SwapInstruction[](len);
        for (uint256 i = 0; i < len; i++) {
            UniswapLib.SwapInstruction memory inst = _input.swapInstructions[len - 1 - i];

            address hopTokenIn = inst.tokenOut;
            address hopTokenOut = inst.tokenIn;

            invertedInstructions[i] = UniswapLib.SwapInstruction({
                protocol: inst.protocol,
                tokenIn: hopTokenIn,
                tokenOut: hopTokenOut,
                amountIn: (i == 0) ? _amount : 0,
                amountOut: 0,
                poolOrPair: inst.poolOrPair,
                fee: inst.fee,
                poolKey: inst.poolKey
            });
        }

        return UniswapLib.SwapInput({
            tokenIn: _input.tokenOut,
            tokenOut: _input.tokenIn,
            swapInstructions: invertedInstructions,
            amountIn0: _amount,
            to: address(this)
        });
    }

    /*
    function collectFeesOnly(UniswapLib.ExecuteCollectFeesOnly calldata _input) public returns (uint256){
        require(_input.swapInput0.tokenOut == _input.swapInput1.tokenOut, "Tokens out are not the same");
        uint256 prevBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));

        positionManager.transferFrom(msg.sender, address(this), _input.collectParams.uniId);

        positionManager.approve(address(liquidityManager), _input.collectParams.uniId);
        (uint256 amount0, uint256 amount1) = liquidityManager.collectV3(_input.collectParams);

        bool isSwapNeeded0 = _input.swapInput0.tokenIn != _input.swapInput0.tokenOut;
        bool isSwapNeeded1 = _input.swapInput1.tokenIn != _input.swapInput1.tokenOut;

        if(isSwapNeeded0 && amount0 > 0) {
            IERC20(_input.swapInput0.tokenIn).safeTransfer(address(swapRouter), amount0);
            UniswapLib.SwapInput memory swap0 = _input.swapInput0;
            swap0.to = address(this);
            swap0.amountIn0 = amount0;
            if(swap0.swapInstructions.length > 0) swap0.swapInstructions[0].amountIn = amount0;
            swapRouter.executeSwap(swap0);
        }
        if(isSwapNeeded1 && amount1 > 0) {
            IERC20(_input.swapInput1.tokenIn).safeTransfer(address(swapRouter), amount1);
            UniswapLib.SwapInput memory swap1 = _input.swapInput1;
            swap1.to = address(this);
            swap1.amountIn0 = amount1;
            if(swap1.swapInstructions.length > 0) swap1.swapInstructions[0].amountIn = amount1;
            swapRouter.executeSwap(swap1);
        }

        uint256 newBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));
        uint256 amount = newBalance - prevBalance;
        IERC20(_input.swapInput0.tokenOut).transfer(msg.sender, amount);

        SendraLib.Position memory position = sendraStorage.getUserPositionById(_input.collectParams.user, _input.collectParams.positionId);
        position.positionData[14] = abi.encode(abi.decode(position.positionData[14], (uint256)) + amount); // feesCollectedUSD (base unit)
        sendraStorage.updateUserFullPosition(_input.collectParams.user, _input.collectParams.positionId, position);
        sendraStorage.applyMetricDelta(_input.collectParams.user, 2, 0, int256(amount));

        positionManager.transferFrom(address(this), msg.sender, _input.collectParams.uniId);
        return amount;
    }
    */

    function withdrawLiquidityAndCollectFees(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata _input)
        public
        returns (
            uint256 amountUsdcReceived,
            SendraLib.Position memory position,
            uint8[] memory gFieldIdsProvider,
            int256[] memory gDeltasProvider
        )
    {
        (amountUsdcReceived, position) = _withdrawLiquidityCore(_input);

        address operator = _input.operator;
        int256 consecutiveLosses = sendraStorage.getUniqueGlobalAccumulator(17, operator);
        int256 maxConsecutiveLosses = sendraStorage.getUniqueGlobalAccumulator(18, operator);
        uint256 lastActivityTimestamp = uint256(sendraStorage.getUniqueGlobalAccumulator(15, operator));

        uint8 pulseLen = position.pnl != 0 ? 6 : 5;
        gFieldIdsProvider = new uint8[](pulseLen);
        gDeltasProvider = new int256[](pulseLen);
        //totalPositionsClosed
        gFieldIdsProvider[0] = 10;
        gDeltasProvider[0] = 1;

        uint8 idx = 1;
        if(position.pnl > 0) {
            //idx == 1 winCount
            gFieldIdsProvider[idx] = 11;
            gDeltasProvider[idx] = 1;
            idx++;
        } else if(position.pnl < 0) {
            //idx == 1 lossCount
            gFieldIdsProvider[idx] = 12;
            gDeltasProvider[idx] = 1;
            idx++;
        }
        // idx == 2 totalDurationSeconds
        gFieldIdsProvider[idx] = 13;
        gDeltasProvider[idx] = int256(block.timestamp - abi.decode(position.positionData[2], (uint256)));
        idx++;
        // idx == 3 lastActivityTimestamp
        gFieldIdsProvider[idx] = 15;
        gDeltasProvider[idx] = int256(block.timestamp - lastActivityTimestamp);
        idx++;
        // idx == 4 consecutiveLosses
        gFieldIdsProvider[idx] = 17;
        // idx == 5 maxConsecutiveLosses
        gFieldIdsProvider[idx + 1] = 18;
        
        if(position.pnl < 0) {
            int256 newStreak = consecutiveLosses + 1;
            gDeltasProvider[idx] = 1;
            gDeltasProvider[idx + 1] = newStreak > maxConsecutiveLosses ? newStreak - maxConsecutiveLosses : int256(0);  
        } else if(position.pnl > 0) {
            gDeltasProvider[idx] = consecutiveLosses > 0 ? -consecutiveLosses : int256(0);
            gDeltasProvider[idx + 1] = 0;
        }

        return (amountUsdcReceived, position, gFieldIdsProvider, gDeltasProvider);
    }

    function withdrawLiquidityAndCollectFeesFromLender(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata _input)
        public
        returns (
            uint256 amountUsdcReceived,
            SendraLib.Position memory position,
            uint8[] memory gFieldIdsProvider,
            int256[] memory gDeltasProvider
        )
    {
        (amountUsdcReceived, position) = _withdrawLiquidityCore(_input);

        gFieldIdsProvider = new uint8[](1);
        gDeltasProvider = new int256[](1);
        gFieldIdsProvider[0] = 9;
        gDeltasProvider[0] = -1;

        return (amountUsdcReceived, position, gFieldIdsProvider, gDeltasProvider);
    }

    function _withdrawLiquidityCore(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata _input)
        internal
        returns (uint256 amountUsdcReceived, SendraLib.Position memory position)
    {
        require(_input.swapInput0.tokenOut == _input.swapInput1.tokenOut, "Tokens out are not the same");
        uint256 prevBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));

        positionManager.transferFrom(msg.sender, address(this), _input.withdrawLiquidityInput.uniId);

        UniswapLib.CollectParams memory _collectParams = UniswapLib.CollectParams(
            _input.withdrawLiquidityInput.uniId,
            _input.withdrawLiquidityInput.positionId,
            false,
            _input.withdrawLiquidityInput.user
        );

        UniswapLib.ExecuteCollectFeesOnly memory executeCollectFeesOnly = UniswapLib.ExecuteCollectFeesOnly(
            _collectParams,
            _input.swapInput0,
            _input.swapInput1
        );

        uint256 feesCollectedUsdc = collectFees(executeCollectFeesOnly);

        positionManager.approve(address(liquidityManager), _input.withdrawLiquidityInput.uniId);
        uint160 sqrtCurrentPrice;
        (position, sqrtCurrentPrice) = liquidityManager.withdrawLiquidityV3(_input.withdrawLiquidityInput);

        UniswapLib.CollectParams memory collectParams = UniswapLib.CollectParams(
            _input.withdrawLiquidityInput.uniId,
            _input.withdrawLiquidityInput.positionId,
            true,
            _input.withdrawLiquidityInput.user
        );

        positionManager.approve(address(liquidityManager), _input.withdrawLiquidityInput.uniId);
        (uint256 amount0, uint256 amount1) = liquidityManager.collectV3(collectParams);

        bool isSwapNeeded0 = _input.swapInput0.tokenIn != _input.swapInput0.tokenOut;
        bool isSwapNeeded1 = _input.swapInput1.tokenIn != _input.swapInput1.tokenOut;

        if(isSwapNeeded0 && amount0 > 0) {
            IERC20(_input.swapInput0.tokenIn).safeTransfer(address(swapRouter), amount0);
            UniswapLib.SwapInput memory swap0 = _input.swapInput0;
            swap0.to = address(this);
            swap0.amountIn0 = amount0;
            if(swap0.swapInstructions.length > 0) swap0.swapInstructions[0].amountIn = amount0;
            swapRouter.executeSwap(swap0);
        }
        if(isSwapNeeded1 && amount1 > 0) {
            IERC20(_input.swapInput1.tokenIn).safeTransfer(address(swapRouter), amount1);
            UniswapLib.SwapInput memory swap1 = _input.swapInput1;
            swap1.to = address(this);
            swap1.amountIn0 = amount1;
            if(swap1.swapInstructions.length > 0) swap1.swapInstructions[0].amountIn = amount1;
            swapRouter.executeSwap(swap1);
        }

        uint256 newBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));
        amountUsdcReceived = newBalance - prevBalance;
        IERC20(_input.swapInput0.tokenOut).transfer(msg.sender, amountUsdcReceived);

        positionManager.transferFrom(address(this), msg.sender, _input.withdrawLiquidityInput.uniId);

        position.isActive = false;
        position.pnl = int256(amountUsdcReceived) - int256(abi.decode(position.positionData[15], (uint256)));

        position.positionData[12] = abi.encode(amountUsdcReceived);
        position.positionData[13] = abi.encode(sqrtCurrentPrice);
        position.positionData[14] = abi.encode(feesCollectedUsdc);
        position.positionData[16] = abi.encode(block.timestamp);
    }

    function collectFees(UniswapLib.ExecuteCollectFeesOnly memory _input) internal returns (uint256){
        require(_input.swapInput0.tokenOut == _input.swapInput1.tokenOut, "Tokens out are not the same");
        uint256 prevBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));

        positionManager.approve(address(liquidityManager), _input.collectParams.uniId);
        (uint256 amount0, uint256 amount1) = liquidityManager.collectV3(_input.collectParams);

        bool isSwapNeeded0 = _input.swapInput0.tokenIn != _input.swapInput0.tokenOut;
        bool isSwapNeeded1 = _input.swapInput1.tokenIn != _input.swapInput1.tokenOut;

        if(isSwapNeeded0 && amount0 > 0) {
            IERC20(_input.swapInput0.tokenIn).safeTransfer(address(swapRouter), amount0);
            UniswapLib.SwapInput memory swap0 = _input.swapInput0;
            swap0.to = address(this);
            swap0.amountIn0 = amount0;
            if(swap0.swapInstructions.length > 0) swap0.swapInstructions[0].amountIn = amount0;
            swapRouter.executeSwap(swap0);
        }
        if(isSwapNeeded1 && amount1 > 0) {
            IERC20(_input.swapInput1.tokenIn).safeTransfer(address(swapRouter), amount1);
            UniswapLib.SwapInput memory swap1 = _input.swapInput1;
            swap1.to = address(this);
            swap1.amountIn0 = amount1;
            if(swap1.swapInstructions.length > 0) swap1.swapInstructions[0].amountIn = amount1;
            swapRouter.executeSwap(swap1);
        }

        uint256 newBalance = IERC20(_input.swapInput0.tokenOut).balanceOf(address(this));
        uint256 amount = newBalance - prevBalance;

        return amount;
    }

}