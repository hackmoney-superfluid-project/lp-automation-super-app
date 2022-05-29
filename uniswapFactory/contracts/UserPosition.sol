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

    /* --- Token Addresses --- */
    address public constant DAI = 0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735;
    address public constant fDAI = 0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7;
    address public constant fDAIx = 0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90;
    address public constant wrappedETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    uint24 public constant poolFee = 3000;

    /* --- Uniswap Contracts --- */
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    ISwapRouter public immutable swapRouter;
    IUniswapV3Factory v3Factory;

    /* --- Deposit Tracking --- */
    struct Deposit {
        uint256 liquidity;
        address token0;
        address token1;
    }

    mapping(uint256 => Deposit) public deposits; // map tokenid of position to the deposit
    uint256[] tokenIdArray; // store tokenIds for iteration over deposits mapping
    uint currentPosition; // the current index of tokenIds (for automation)

    /* --- Other Contract Storage --- */
    ISuperToken acceptedToken; // the accepted super token

    address userAddress; // owner address

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
    }

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
        tokenIdArray.push(tokenId);
    }

    // to be used by frontend, creates a Deposit struct that will be turned into an actual position by the automation
    function orderNewDeposit(address token0, address token1) external {

        // find a fake token id that is guaranteed not to overwrite a deposit in the mapping
        // TODO: there's probably a better way to do this
        // TODO: check that position w/ these tokens doesn't already exist
        uint256 tempTokenId = 0;
        for (uint i = 0; i < tokenIdArray.length; i++) {
            tempTokenId += tokenIdArray[i];
        }

        deposits[tempTokenId] = Deposit({liquidity: 0, token0: token0, token1: token1});
        tokenIdArray.push(tempTokenId);
    }

    // mint the position on uniswap
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

    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        internal
    {
        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amountAdd0,
                amount1Desired: amountAdd1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        nonfungiblePositionManager.increaseLiquidity(params);

        // this will overwrite the Deposit struct with updated data about the position
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

        // swap downgraded tokens w/ tokens from liquidity pair
        address underlyingToken = acceptedToken.getUnderlyingToken();
        Deposit memory currentDeposit = deposits[ tokenIdArray[currentPosition] ];
        uint256 underlyingContractBalance = IERC20(underlyingToken).balanceOf(address(this));

        // TODO: use oralces to calculate the proper ratio of each asset (just going 50/50 here for testing)
        // assume here that if the streamed token is part of the pair, it should be token0
        if (underlyingToken == currentDeposit.token0) {
            swapExactInputSingle(underlyingToken, currentDeposit.token1, underlyingContractBalance / 2);
        } else {
            swapExactInputSingle(underlyingToken, currentDeposit.token0, underlyingContractBalance / 2);
            swapExactInputSingle(underlyingToken, currentDeposit.token1, underlyingContractBalance / 2);
        }

        // get updated amounts of each token
        uint256 in1 = IERC20(currentDeposit.token0).balanceOf(address(this));
        uint256 in2 = IERC20(currentDeposit.token1).balanceOf(address(this));

        // only create/update position if balance of both tokens is > 0
        if (in1 > 0 && in2 > 0) {

            // either create a position or update an outstanding one
            // TODO: check this: this logic is based on the assumption that the liquidity field of Deposit will be init to 0 (and will not be 0 after adding liquidity)
            if (currentDeposit.liquidity == 0) {
                // remove temporary deposit struct
                delete( deposits[ tokenIdArray[currentPosition] ] );
                delete( tokenIdArray[currentPosition] );

                mintNewPosition(in1, in2, currentDeposit.token0, currentDeposit.token1);
            } else {
                increaseLiquidityCurrentRange(tokenIdArray[currentPosition], in1, in2);
            }
        }

        // increment current position
        ++currentPosition;
        if(currentPosition >= tokenIdArray.length){
            currentPosition = 0;
        }
    }
}
