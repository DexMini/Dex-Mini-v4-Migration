// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../src/interfaces/IV3PositionManager.sol";
import "../../src/interfaces/IV4PoolManager.sol";
import "../../src/interfaces/IV4Vault.sol";

contract MockV3PositionManager is IV3PositionManager {
    mapping(uint256 => Position) private _positions;
    mapping(uint256 => address) public ownerOf;

    function createPosition(
        uint256 tokenId,
        address owner,
        address _token0,
        address _token1,
        uint128 _liquidity
    ) external {
        _positions[tokenId] = Position({
            nonce: 0,
            operator: address(0),
            token0: _token0,
            token1: _token1,
            fee: 3000,
            tickLower: -1000,
            tickUpper: 1000,
            liquidity: _liquidity,
            feeGrowthInside0LastX128: 0,
            feeGrowthInside1LastX128: 0,
            tokensOwed0: 0,
            tokensOwed1: 0
        });
        ownerOf[tokenId] = owner;
    }

    function positions(uint256 tokenId) external view override returns (Position memory) {
        return _positions[tokenId];
    }

    function decreaseLiquidity(
        uint256 tokenId,
        uint128 liquidity,
        uint256,
        uint256,
        uint256
    ) external override returns (uint256 amount0, uint256 amount1) {
        require(_positions[tokenId].liquidity >= liquidity, "Insufficient liquidity");
        _positions[tokenId].liquidity -= liquidity;
        return (liquidity, liquidity); // Simplified 1:1 ratio
    }

    function collect(
        uint256,
        address,  // recipient - unused
        uint128 amount0Max,
        uint128 amount1Max
    ) external pure override returns (uint256, uint256) {
        return (uint256(amount0Max), uint256(amount1Max));
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        require(ownerOf[tokenId] == from, "Not owner");
        ownerOf[tokenId] = to;
    }
}

contract MockV4PoolManager is IV4PoolManager {
    function initialize(PoolKey calldata, uint160) external pure {}
    
    function lock(bytes calldata) external pure returns (bytes memory) {
        return "";
    }
    
    function mint(MintParams calldata) external pure returns (uint256, uint256) {
        return (0, 0);
    }
}

contract MockV4Vault is IV4Vault {
    function deposit(address, uint256) external pure {}
} 