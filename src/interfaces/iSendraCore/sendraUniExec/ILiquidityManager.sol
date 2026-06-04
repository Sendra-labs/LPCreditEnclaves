// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { UniswapLib } from "../../../libs/uni.lib.sol";
import { SendraLib } from "../../../libs/Sendra.lib.sol";

/// @notice External surface of protocol `LiquidityManager` (Uniswap V3 mint / decrease / collect).
interface ILiquidityManager {
    function slippageBps() external view returns (uint256);

    function setSlippageBps(uint256 slippageBps) external;

    function addLiquidityV3(UniswapLib.ProvideLiquidityInput calldata input)
        external
        returns (
            uint256 tokenId,
            uint256 amountDeposited0,
            uint256 amountDeposited1,
            uint160 sqrtCurrentPrice,
            address pool,
            uint256 amountLeftToken0,
            uint256 amountLeftToken1
        );

    function withdrawLiquidityV3(UniswapLib.WithdrawLiquidityInput calldata input)
        external
        returns (SendraLib.Position memory position, uint160 sqrtCurrentPrice);

    function collectV3(UniswapLib.CollectParams calldata input)
        external
        returns (uint256 amount0, uint256 amount1);
}
