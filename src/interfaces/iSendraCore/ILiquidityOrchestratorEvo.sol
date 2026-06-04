// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { UniswapLib } from "../../libs/uni.lib.sol";
import { SendraLib } from "../../libs/Sendra.lib.sol";

/// @notice Liquidity Orchestrator Evo — provide / collect / withdraw Uniswap V3 positions.
interface ILiquidityOrchestratorEvo {
    function provideLiquidity(UniswapLib.ExecuteProvideLiquidityInput calldata _input)
        external
        returns (bytes[] memory positionData, uint8[] memory gFieldIdsProvider, int256[] memory gDeltasProvider);

    function invertSwapInput(UniswapLib.SwapInput memory _input, uint256 _amount)
        external
        view
        returns (UniswapLib.SwapInput memory);

    function collectFeesOnly(UniswapLib.ExecuteCollectFeesOnly calldata _input) external returns (uint256 amount);

    function withdrawLiquidityAndCollectFees(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata _input)
        external
        returns (
            uint256 amountUsdcReceived,
            SendraLib.Position memory position,
            uint8[] memory gFieldIdsProvider,
            int256[] memory gDeltasProvider
        );

    function withdrawLiquidityAndCollectFeesFromLender(UniswapLib.ExecuteWithdrawLiquidityAndCollectFees calldata _input)
        external
        returns (
            uint256 amountUsdcReceived,
            SendraLib.Position memory position,
            uint8[] memory gFieldIdsProvider,
            int256[] memory gDeltasProvider
        );
}
