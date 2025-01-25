// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IV4PoolManager {
    struct PoolKey {
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
        address hook;
    }
    
    struct MintParams {
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    
    function initialize(PoolKey calldata key, uint160 sqrtPriceX96) external;
    function lock(bytes calldata data) external returns (bytes memory);
    function mint(MintParams calldata params) external returns (uint256 amount0, uint256 amount1);
} 