// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

contract UniswapV3PriceOracle {
    address public immutable token0;
    address public immutable token1;
    address public immutable pool;

    // TODO: Move get pool into seperate function as opposed to the hardcoding in the constructor. This will enable us to dynamically choose pairs
    constructor(address _factory, address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        address _pool = IUniswapV3Factory(_factory).getPool(
            _token0,
            _token1,
            _fee
        );
        require(_pool != address(0), 'Pool does not exist');

        pool = _pool;
    }

    function estimateAmountOut(
        address tokenIn,
        uint128 amountIn,
        uint32 secondsAgo // duration of the TWAP - Time-weighted average price
    ) external view returns (uint amountOut) {
        require(tokenIn == token0 || tokenIn == token1, 'Invalid token');
        address tokenOut = tokenIn == token0 ? token1 : token0;

        // Some of this code is copied from the UniswapV3 Oracle library
        // we save gas by removing the code that calculates the harmonic mean liquidity
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 tick = int24(tickCumulativesDelta / secondsAgo);
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % secondsAgo != 0)) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }
}