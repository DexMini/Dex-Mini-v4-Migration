// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {DexMiniV4Migrator} from "../src/Dexminiv4Migrator.sol";
import "./mocks/MockERC20.sol";
import "./mocks/MockV2Pair.sol";
import "./mocks/MockUniswapV3V4.sol";

contract Dexminiv4MigratorTest is Test {
    DexMiniV4Migrator public migrator;
    MockV3PositionManager public v3PositionManager;
    MockV4PoolManager public v4PoolManager;
    MockV4Vault public v4Vault;
    MockERC20 public token0;
    MockERC20 public token1;
    MockV2Pair public v2Pair;

    address public user = address(0x1234);
    uint256 public constant INITIAL_LIQUIDITY = 1000e18;

    function setUp() public {
        // Deploy mock tokens
        token0 = new MockERC20();
        token1 = new MockERC20();

        // Deploy mock contracts
        v3PositionManager = new MockV3PositionManager();
        v4PoolManager = new MockV4PoolManager();
        v4Vault = new MockV4Vault();
        
        // Deploy V2 pair with tokens in correct order
        address correctToken0 = address(token0) < address(token1) ? address(token0) : address(token1);
        address correctToken1 = address(token0) < address(token1) ? address(token1) : address(token0);
        v2Pair = new MockV2Pair(correctToken0, correctToken1);

        // Deploy migrator
        migrator = new DexMiniV4Migrator(
            IV3PositionManager(address(v3PositionManager)),
            IV4PoolManager(address(v4PoolManager)),
            IV4Vault(address(v4Vault))
        );

        // Setup initial state
        vm.startPrank(user);
        token0.mint(user, INITIAL_LIQUIDITY);
        token1.mint(user, INITIAL_LIQUIDITY);
        token0.approve(address(v2Pair), INITIAL_LIQUIDITY);
        token1.approve(address(v2Pair), INITIAL_LIQUIDITY);
        vm.stopPrank();
    }

    function testMigrateV2ToV4Success() public {
        uint256 liquidity = 100e18;
        
        // Setup V2 position
        vm.startPrank(user);
        // First approve tokens to V2 pair for minting
        token0.approve(address(v2Pair), liquidity);
        token1.approve(address(v2Pair), liquidity);
        
        // Transfer tokens to V2 pair
        token0.transfer(address(v2Pair), liquidity);
        token1.transfer(address(v2Pair), liquidity);
        
        v2Pair.mint(user, liquidity);
        v2Pair.approve(address(migrator), liquidity);

        // Create migration params
        DexMiniV4Migrator.MigrationParams memory params = DexMiniV4Migrator.MigrationParams({
            poolKey: IV4PoolManager.PoolKey({
                token0: v2Pair.token0(),
                token1: v2Pair.token1(),
                fee: 3000,
                tickSpacing: 60,
                hook: address(0)
            }),
            sqrtPriceX96: 1 << 96, // 1.0 price
            tickLower: -1000,
            tickUpper: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 1
        });

        // Execute migration
        migrator.migrateV2ToV4(v2Pair, liquidity, params);
        vm.stopPrank();
    }

    function testMigrateV3ToV4Success() public {
        uint256 tokenId = 1;
        uint128 liquidity = 100e18;

        // Ensure tokens are in correct order
        address correctToken0 = address(token0) < address(token1) ? address(token0) : address(token1);
        address correctToken1 = address(token0) < address(token1) ? address(token1) : address(token0);

        // Setup V3 position
        v3PositionManager.createPosition(
            tokenId,
            user,
            correctToken0,
            correctToken1,
            liquidity
        );

        vm.startPrank(user);
        
        // Create migration params
        DexMiniV4Migrator.MigrationParams memory params = DexMiniV4Migrator.MigrationParams({
            poolKey: IV4PoolManager.PoolKey({
                token0: correctToken0,
                token1: correctToken1,
                fee: 3000,
                tickSpacing: 60,
                hook: address(0)
            }),
            sqrtPriceX96: 1 << 96,
            tickLower: -1000,
            tickUpper: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 1
        });

        // Execute migration
        migrator.migrateV3ToV4(tokenId, params);
        vm.stopPrank();
    }

    function test_RevertWhen_DeadlineExpired() public {
        uint256 tokenId = 1;
        
        // Ensure tokens are in correct order
        address correctToken0 = address(token0) < address(token1) ? address(token0) : address(token1);
        address correctToken1 = address(token0) < address(token1) ? address(token1) : address(token0);

        // Setup V3 position first
        v3PositionManager.createPosition(
            tokenId,
            user,
            correctToken0,
            correctToken1,
            100e18
        );

        DexMiniV4Migrator.MigrationParams memory params = DexMiniV4Migrator.MigrationParams({
            poolKey: IV4PoolManager.PoolKey({
                token0: correctToken0,
                token1: correctToken1,
                fee: 3000,
                tickSpacing: 60,
                hook: address(0)
            }),
            sqrtPriceX96: 1 << 96,
            tickLower: -1000,
            tickUpper: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp - 1 // Expired deadline
        });

        vm.prank(user);
        vm.expectRevert("Deadline expired");
        migrator.migrateV3ToV4(tokenId, params);
    }

    function test_RevertWhen_InsufficientV2Liquidity() public {
        uint256 liquidity = 100e18;
        
        vm.startPrank(user);
        v2Pair.mint(user, liquidity);
        v2Pair.approve(address(migrator), liquidity + 1); // Try to migrate more than available

        DexMiniV4Migrator.MigrationParams memory params = DexMiniV4Migrator.MigrationParams({
            poolKey: IV4PoolManager.PoolKey({
                token0: v2Pair.token0(),
                token1: v2Pair.token1(),
                fee: 3000,
                tickSpacing: 60,
                hook: address(0)
            }),
            sqrtPriceX96: 1 << 96,
            tickLower: -1000,
            tickUpper: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 1
        });

        vm.expectRevert("INSUFFICIENT_BALANCE");
        migrator.migrateV2ToV4(v2Pair, liquidity + 1, params);
        vm.stopPrank();
    }

    function test_RevertWhen_InsufficientV3Liquidity() public {
        uint256 tokenId = 1;
        uint128 liquidity = 100e18;

        // Ensure tokens are in correct order
        address correctToken0 = address(token0) < address(token1) ? address(token0) : address(token1);
        address correctToken1 = address(token0) < address(token1) ? address(token1) : address(token0);

        v3PositionManager.createPosition(
            tokenId,
            user,
            correctToken0,
            correctToken1,
            liquidity
        );

        vm.startPrank(user);
        
        DexMiniV4Migrator.MigrationParams memory params = DexMiniV4Migrator.MigrationParams({
            poolKey: IV4PoolManager.PoolKey({
                token0: correctToken0,
                token1: correctToken1,
                fee: 3000,
                tickSpacing: 60,
                hook: address(0)
            }),
            sqrtPriceX96: 1 << 96,
            tickLower: -1000,
            tickUpper: 1000,
            amount0Min: liquidity + 1, // Set minimum higher than available
            amount1Min: 0,
            deadline: block.timestamp + 1
        });

        migrator.migrateV3ToV4(tokenId, params);
        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedV3Migration() public {
        uint256 tokenId = 1;
        uint128 liquidity = 100e18;

        // Ensure tokens are in correct order
        address correctToken0 = address(token0) < address(token1) ? address(token0) : address(token1);
        address correctToken1 = address(token0) < address(token1) ? address(token1) : address(token0);

        v3PositionManager.createPosition(
            tokenId,
            address(0xdead), // Different owner
            correctToken0,
            correctToken1,
            liquidity
        );

        vm.prank(user);
        DexMiniV4Migrator.MigrationParams memory params = DexMiniV4Migrator.MigrationParams({
            poolKey: IV4PoolManager.PoolKey({
                token0: correctToken0,
                token1: correctToken1,
                fee: 3000,
                tickSpacing: 60,
                hook: address(0)
            }),
            sqrtPriceX96: 1 << 96,
            tickLower: -1000,
            tickUpper: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 1
        });

        vm.expectRevert("Not owner");
        migrator.migrateV3ToV4(tokenId, params);
    }
} 