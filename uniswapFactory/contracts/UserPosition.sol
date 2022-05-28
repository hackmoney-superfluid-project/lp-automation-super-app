// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// Provide liquidity contracts
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";

// Swap contracts (swap functions also uses TransferHelper.sol from above imports)
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';

import './ISuperToken.sol';
import './KeeperCompatibleInterface.sol';
import './IUniswapV2Router02.sol';
import './IUniswapV2Factory.sol';

//LiquidityManagement
contract UserPosition is IERC721Receiver {

    /* --- Chain link --- */
    // Used to ensure that the upkeep is perfomed every __interval__ seconds
    uint256 public immutable interval;
    uint256 public lastTimeStamp;

    /* --- Token Addresses --- */
    address public constant DAI = 0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735;
    address public constant fDAI = 0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7;
    address public constant fDAIx = 0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90;
    address public constant wrappedETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    uint24 public constant poolFee = 3000;

    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    ISwapRouter public immutable swapRouter;
    //address private constant uniswapV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    //address private constant uniswapV2RouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    // Stores a deposit of a token pair
    struct Deposit {
        uint256 liquidity;
        address token0;
        address token1;
    }

    // map tokenid of position to the deposit
    mapping(uint256 => Deposit) public deposits;

    // the accepted super token
    ISuperToken acceptedToken;

    // owner address
    address userAddress;

    // uniswap v2 router
    //IUniswapV2Router02 router;

    // v3 factory for getting pool
    IUniswapV3Factory v3Factory;

    // temp event for logging info
    event Log(string message, uint val);

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISuperToken _acceptedToken,
        address _userAddress,
        ISwapRouter _swapRouter,
        IUniswapV3Factory _v3Factory
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        acceptedToken = _acceptedToken;
        userAddress = _userAddress;
        swapRouter = _swapRouter;
        v3Factory = _v3Factory;

        interval = 60;
        lastTimeStamp = block.timestamp;
    }

    /* UNI V2 --remove later
    function provideLiquidity(uint256 amount0ToMint, uint256 amount1ToMint, address _token0, address _token1)
        internal
    {
        // Approve the position manager
        TransferHelper.safeApprove(
            _token0,
            address(router),
            amount0ToMint
        );
        TransferHelper.safeApprove(
            _token1,
            address(router),
            amount1ToMint
        );

        (uint amountA, uint amountB, uint liquidity) = router.addLiquidity(_token0, _token1, amount0ToMint, amount1ToMint, 0, 0, address(this), block.timestamp);

        // Update position if it already exists
        if (deposits[_token1].token0 == _token0) {
            deposits[_token1].amount0 += amountA;
            deposits[_token1].amount1 += amountB;
            // Would this work? : deposits[_token1].liquidity += liquidity;
        } else {
            deposits[_token1] = Deposit({
                liquidity: liquidity,
                token0: _token0,
                token1: _token1,
                amount0: amountA,
                amount1: amountB
            });
        }
    }

    function removeLiquidity(address _token0, address _token1) external {
        address pair = IUniswapV2Factory(uniswapV2FactoryAddress).getPair(_token0, _token1);

        uint256 liquidity = IERC20(pair).balanceOf(address(this));
        IERC20(pair).approve(uniswapV2RouterAddress, liquidity);

        (uint amountA, uint amountB) = 
            router.removeLiquidity(
                _token0,
                _token1,
                liquidity, 
                0, 
                0, 
                address(this), 
                block.timestamp
            );

        IERC20(_token0).transfer(userAddress, amountA);
        IERC20(_token1).transfer(userAddress, amountB);
        emit Log('amountA', amountA);
        emit Log('amountB', amountB);
    }*/

    // implementing onERC721Received so this contract can receive custody of erc721 tokens
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        _createDeposit(tokenId);
        return this.onERC721Received.selector;
    }

    // helper method for retreiving details of erc721 token and storing in deposits mapping
    function _createDeposit(uint256 tokenId) internal {
        (, , address token0, address token1, , , , uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(tokenId);
        deposits[tokenId] = Deposit({liquidity: liquidity, token0: token0, token1: token1});
    }

    // mint the position
    function mintNewPosition(uint256 amount0ToMint, uint256 amount1ToMint, address _token0, address _token1) internal {

        // Approve the position manager
        TransferHelper.safeApprove(_token0, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(_token1, address(nonfungiblePositionManager), amount1ToMint);

        // Get pool
        IUniswapV3Pool pool = IUniswapV3Pool(v3Factory.getPool(_token0, _token1, poolFee));
        int24 tickSpacing = pool.tickSpacing();

        int24 lower = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 upper = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: _token0,
                token1: _token1,
                fee: poolFee,
                tickLower: lower,
                tickUpper: upper,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = nonfungiblePositionManager.mint(params);

        _createDeposit(tokenId);
    }

    function swapExactInputSingle(address _tokenIn, address _tokenOut, uint256 amountIn) private returns (uint256 amountOut) {

        // Approve the router to spend first token
        TransferHelper.safeApprove(_tokenIn, address(swapRouter), amountIn);

        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: wrappedETH,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    function maintainPosition() external {
        // downgrade super tokens
        acceptedToken.downgrade(acceptedToken.balanceOf(address(this)));

        // get underlying token of super token and swap half with WETH
        address underlyingToken = acceptedToken.getUnderlyingToken();
        uint256 underlyingContractBalance = IERC20(underlyingToken).balanceOf(address(this));
        uint256 amountToSwap = underlyingContractBalance / 2;
        uint256 amountSwapped = swapExactInputSingle(underlyingToken, wrappedETH, amountToSwap);

        // Provide liquidity if contract has balance of both tokens
        uint256 in1 = IERC20(underlyingToken).balanceOf(address(this));
        uint256 in2 = IERC20(wrappedETH).balanceOf(address(this));
        if (in1 > 0 && in2 > 0) {
            //provideLiquidity(in1, in2, underlyingToken, wrappedETH);
            mintNewPosition(in1, in2, underlyingToken, wrappedETH);
        }
    }
}
