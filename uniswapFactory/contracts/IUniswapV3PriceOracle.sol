interface IUniswapV3PriceOracle {
    function estimateAmountOut(
        address tokenIn,
        address tokenOut,
        uint128 amountIn,
        uint32 secondsAgo,
        uint24 poolFee
    ) external view returns (uint amountOut);
}