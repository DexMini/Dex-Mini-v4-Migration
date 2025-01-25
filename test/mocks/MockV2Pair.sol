// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../src/interfaces/IUniswapV2Pair.sol";
import "./MockERC20.sol";

contract MockV2Pair is IUniswapV2Pair {
    address public override token0;
    address public override token1;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function burn(address to) external override returns (uint256 amount0, uint256 amount1) {
        uint256 liquidity = balanceOf[msg.sender];
        amount0 = liquidity; // Simplified: 1:1 ratio for testing
        amount1 = liquidity;
        balanceOf[msg.sender] -= liquidity;
        totalSupply -= liquidity;
        MockERC20(token0).transfer(to, amount0);
        MockERC20(token1).transfer(to, amount1);
        return (amount0, amount1);
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        require(balanceOf[from] >= value, "INSUFFICIENT_BALANCE");
        require(allowance[from][msg.sender] >= value, "INSUFFICIENT_ALLOWANCE");
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
} 