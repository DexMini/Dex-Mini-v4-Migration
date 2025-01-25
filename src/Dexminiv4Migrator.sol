// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/*////////////////////////////////////////////////////////////////////////////
//                                                                          //
//     ██████╗ ███████╗██╗  ██╗    ███╗   ███╗██╗███╗   ██╗██╗           //
//     ██╔══██╗██╔════╝╚██╗██╔╝    ████╗ ████║██║████╗  ██║██║           //
//     ██║  ██║█████╗   ╚███╔╝     ██╔████╔██║██║██╔██╗ ██║██║           //
//     ██║  ██║██╔══╝   ██╔██╗     ██║╚██╔╝██║██║██║╚██╗██║██║           //
//     ██████╔╝███████╗██╔╝ ██╗    ██║ ╚═╝ ██║██║██║ ╚████║██║           //
//     ╚═════╝ ╚══════╝╚═╝  ╚═╝    ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝           //
//                                                                          //
//     Uniswap V2\3 Liquidity Migration to v4 - Version 1.0                           //
//     https://dexmini.com                                                 //
//                                                                          //
////////////////////////////////////////////////////////////////////////////*/


// External imports for token standards and interfaces
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IV3PositionManager.sol";
import "./interfaces/IV4PoolManager.sol";
import "./interfaces/IV4Vault.sol";

/// @title Dex Mini Protocol (DMI) v1.0 
/// @author Josue <josue@dexmini.com>
/// @notice This contract provides a foundation for Uniswap V2 and V3 liquidity migration while maintaining security and flexibility for different pool configurations in Uniswap V4.
/// @dev This contract handles the migration of liquidity positions from Uniswap V2 and V3 to V4,
///      including the necessary token transfers, position management, and safety checks.
contract DexMiniV4Migrator is IERC721Receiver {
    using SafeERC20 for IERC20;
    
    // Core protocol contracts that this migrator interacts with
    IV3PositionManager public immutable v3PositionManager;
    IV4PoolManager public immutable v4PoolManager;
    IV4Vault public immutable v4Vault;
    
    /// @notice Parameters required for migration to V4
    /// @param poolKey The pool configuration for V4
    /// @param sqrtPriceX96 The initial sqrt price for the pool, encoded as a Q64.96
    /// @param tickLower The lower tick of the position
    /// @param tickUpper The upper tick of the position
    /// @param amount0Min The minimum amount of token0 to receive
    /// @param amount1Min The minimum amount of token1 to receive
    /// @param deadline The timestamp by which the transaction must be executed
    struct MigrationParams {
        IV4PoolManager.PoolKey poolKey;
        uint160 sqrtPriceX96;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /// @notice Constructs the migrator with necessary contract references
    /// @param _v3PositionManager The V3 NonfungiblePositionManager contract
    /// @param _v4PoolManager The V4 PoolManager contract
    /// @param _v4Vault The V4 Vault contract for token deposits
    constructor(IV3PositionManager _v3PositionManager, IV4PoolManager _v4PoolManager, IV4Vault _v4Vault) {
        v3PositionManager = _v3PositionManager;
        v4PoolManager = _v4PoolManager;
        v4Vault = _v4Vault;
    }

    /// @notice Migrates liquidity from a V2 pair to a V4 position
    /// @dev Transfers V2 LP tokens, burns them for underlying assets, and creates a V4 position
    /// @param v2Pair The V2 pair contract to migrate from
    /// @param liquidity The amount of V2 LP tokens to migrate
    /// @param params The parameters for creating the V4 position
    function migrateV2ToV4(
        IUniswapV2Pair v2Pair,
        uint256 liquidity,
        MigrationParams calldata params
    ) external {
        require(block.timestamp <= params.deadline, "Deadline expired");
        
        // Validate token order and match
        address token0 = v2Pair.token0();
        address token1 = v2Pair.token1();
        _validatePoolParams(params.poolKey, token0, token1);

        // Transfer and burn V2 LP tokens
        v2Pair.transferFrom(msg.sender, address(this), liquidity);
        (uint256 amount0, uint256 amount1) = v2Pair.burn(address(this));

        // Deposit tokens to V4 Vault
        _depositToVault(token0, amount0);
        _depositToVault(token1, amount1);

        // Create V4 position
        _createV4Position(
            params,
            amount0,
            amount1,
            msg.sender
        );
    }

    /// @notice Migrates a V3 position to V4
    /// @dev Transfers V3 NFT, withdraws liquidity, and creates a V4 position
    /// @param tokenId The ID of the V3 position NFT
    /// @param params The parameters for creating the V4 position
    function migrateV3ToV4(
        uint256 tokenId,
        MigrationParams calldata params
    ) external {
        require(block.timestamp <= params.deadline, "Deadline expired");
        
        // Get position details
        IV3PositionManager.Position memory position = v3PositionManager.positions(tokenId);
        _validatePoolParams(params.poolKey, position.token0, position.token1);

        // Transfer NFT to contract
        v3PositionManager.safeTransferFrom(msg.sender, address(this), tokenId);

        // Withdraw liquidity from V3
        (uint256 amount0, uint256 amount1) = v3PositionManager.decreaseLiquidity(
            tokenId,
            position.liquidity,
            0,
            0,
            params.deadline
        );

        // Collect owed tokens
        (uint256 collected0, uint256 collected1) = v3PositionManager.collect(
            tokenId,
            address(this),
            type(uint128).max,
            type(uint128).max
        );

        uint256 total0 = amount0 + collected0;
        uint256 total1 = amount1 + collected1;

        // Deposit to V4 Vault
        _depositToVault(position.token0, total0);
        _depositToVault(position.token1, total1);

        // Create V4 position
        _createV4Position(
            params,
            total0,
            total1,
            msg.sender
        );
    }

    /// @notice Creates a new position in V4
    /// @dev Initializes pool if needed and mints new position
    /// @param params Migration parameters including pool configuration
    /// @param amount0 Amount of token0 to use
    /// @param amount1 Amount of token1 to use
    /// @param recipient Address to receive the V4 position
    function _createV4Position(
        MigrationParams calldata params,
        uint256 amount0,
        uint256 amount1,
        address recipient
    ) internal {
        // Initialize pool if not exists
        try v4PoolManager.initialize(params.poolKey, params.sqrtPriceX96) {} catch {}
        
        // Prepare mint parameters
        IV4PoolManager.MintParams memory mintParams = IV4PoolManager.MintParams({
            key: params.poolKey,
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: params.amount0Min,
            amount1Min: params.amount1Min,
            recipient: recipient,
            deadline: params.deadline
        });

        // Execute mint through PoolManager
        v4PoolManager.mint(mintParams);
    }

    /// @notice Deposits tokens into the V4 vault
    /// @dev Approves and deposits tokens to the V4 vault
    /// @param token The token to deposit
    /// @param amount The amount to deposit
    function _depositToVault(address token, uint256 amount) internal {
        IERC20(token).approve(address(v4Vault), amount);
        v4Vault.deposit(token, amount);
    }

    /// @notice Validates that the pool parameters match the token pair
    /// @dev Ensures tokens are in correct order and match the pool key
    /// @param key The pool key containing token addresses
    /// @param token0 First token address
    /// @param token1 Second token address
    function _validatePoolParams(IV4PoolManager.PoolKey memory key, address token0, address token1) internal pure {
        require(key.token0 == token0 && key.token1 == token1, "Token mismatch");
        require(key.token0 < key.token1, "Tokens not sorted");
    }

    /// @notice Required for receiving ERC721 tokens (V3 positions)
    /// @dev Implementation of IERC721Receiver
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}