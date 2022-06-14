// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

contract UniswapV3PriceOracle {
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }

    function estimateAmountOut(
        address _tokenIn,
        address _tokenOut,
        uint128 _amountIn,
        uint32 _secondsAgo, // duration of the TWAP - Time-weighted average price
        uint24 _fee
    ) external view returns (uint amountOut) {
        address pool = IUniswapV3Factory(factory).getPool(
            _tokenIn,
            _tokenOut,
            _fee
        );
        require(pool != address(0), 'Pool does not exist');

        // Some of this code is copied from the UniswapV3 Oracle library
        // we save gas by removing the code that calculates the harmonic mean liquidity
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = _secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        int24 tick = int24(tickCumulativesDelta / _secondsAgo);
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % _secondsAgo != 0)) {
            tick--;
        }

        amountOut = OracleLibrary.getQuoteAtTick(tick, _amountIn, _tokenIn, _tokenOut);
    }
}