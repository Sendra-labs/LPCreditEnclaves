// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal ERC721 surface used with Uniswap V3 NonfungiblePositionManager.
interface IUniswapV3PositionNFT {
    function transferFrom(address from, address to, uint256 tokenId) external;

    function approve(address to, uint256 tokenId) external;
}
