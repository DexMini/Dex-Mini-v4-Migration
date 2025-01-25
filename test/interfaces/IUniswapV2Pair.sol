// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
} 