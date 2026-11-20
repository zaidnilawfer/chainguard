// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockSwap
 * @notice Simulates a simple DEX swap — used to test ChainGuard
 *         policy enforcement on token-swap actions.
 */
contract MockSwap {
    event Swapped(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @notice Execute a 1:1 mock swap (no real pricing).
     */
    function swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external returns (uint256 amountOut) {
        require(_amountIn > 0, "Amount must be > 0");

        IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn);

        // 1:1 mock rate
        amountOut = _amountIn;
        IERC20(_tokenOut).transfer(msg.sender, amountOut);

        emit Swapped(msg.sender, _tokenIn, _tokenOut, _amountIn, amountOut);
    }
}
