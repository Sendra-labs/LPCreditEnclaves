// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { UniswapLib } from "./uni.lib.sol";

/// @notice ABI of SendraAccount LP calls. Field order matches markets `LpAccountTypes`.
library AccountLp {
    struct ProvideLiquidityInput {
        UniswapLib.Protocol protocol;
        address token0;
        address token1;
        address recipient;
        address user;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct ExecuteProvideLiquidityInput {
        UniswapLib.SwapInput swapInput0;
        UniswapLib.SwapInput swapInput1;
        UniswapLib.SwapInput invertedSwapInput0;
        UniswapLib.SwapInput invertedSwapInput1;
        ProvideLiquidityInput provideLiquidityInput;
    }

    struct PartialCloseInput {
        uint256 uniId;
        uint256 positionId;
        address user;
    }

    struct SellHeldInput {
        uint256 positionId;
        address user;
        UniswapLib.SwapInput swapInput0;
        UniswapLib.SwapInput swapInput1;
    }

    struct WithdrawInput {
        uint256 uniId;
        uint256 positionId;
        address user;
    }

    struct ExecuteWithdrawLiquidityAndCollectFees {
        WithdrawInput withdrawInput;
        UniswapLib.SwapInput swapInput0;
        UniswapLib.SwapInput swapInput1;
    }
}

interface ISendraLpAccount {
    function provide(AccountLp.ExecuteProvideLiquidityInput calldata input) external returns (uint256 positionId);
    function partialClose(AccountLp.PartialCloseInput calldata input) external;
    function sellHeld(AccountLp.SellHeldInput calldata input) external returns (uint256 baseOut);
    function withdraw(AccountLp.ExecuteWithdrawLiquidityAndCollectFees calldata input) external returns (uint256 baseOut);
}
