// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// Provide liquidity contracts
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/base/LiquidityManagement.sol";

// Swap contracts (swap functions also uses TransferHelper.sol from above imports)
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./ISuperToken.sol";
import "./KeeperCompatibleInterface.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV3PriceOracle.sol";

//LiquidityManagement
contract UserPosition is IERC721Receiver {
    /* --- Token Addresses --- */
    address public constant DAI = 0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735;
    address public constant fDAI = 0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7;
    address public constant fDAIx = 0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90;
    address public constant wrappedETH =
        0xc778417E063141139Fce010982780140Aa0cD5Ab;
    uint24 public constant poolFee = 3000;

    /* --- Uniswap Contracts --- */
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    ISwapRouter public immutable swapRouter;
    IUniswapV3Factory v3Factory;
    address uniswapV3PriceOracle;

    /* --- Deposit Tracking --- */
    enum DepositType {
        UNISWAPv3_LP,
        TOKEN
    }
    struct Deposit {
        DepositType depositType;
        uint256 liquidity;
        address token0;
        address token1;
        uint256 tokenId;
    }

    //mapping(uint256 => Deposit) public deposits; // map tokenid of position to the deposit
    //uint256[] tokenIdArray; // store tokenIds for iteration over deposits mapping
    mapping(uint256 => Deposit) public deposits; // map (token0 + token1) to deposit
    uint256[] hashArray; // store hashes (token0 + token1) for iteration over deposits mapping
    uint256 currentPosition = 0; // the current index in the hashArray (for automation)

    /* --- Other Contract Storage --- */
    ISuperToken acceptedToken; // the accepted super token

    address userAddress; // owner address

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISuperToken _acceptedToken,
        address _userAddress,
        ISwapRouter _swapRouter,
        IUniswapV3Factory _v3Factory,
        address _uniswapV3PriceOracle
    ) {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        acceptedToken = _acceptedToken;
        userAddress = _userAddress;
        swapRouter = _swapRouter;
        v3Factory = _v3Factory;
        uniswapV3PriceOracle = _uniswapV3PriceOracle;
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

    // helper function to compute the hash for a given position
    function _computeHash(address token0, address token1)
        internal
        returns (uint256)
    {
        return uint256(token0) + uint256(token1);
    }

    // gets number of deposits
    function getNumDeposits() public view returns (uint256) {
        return hashArray.length;
    }

    // helper method for retreiving details of erc721 token and storing in deposits mapping
    function _createDeposit(uint256 tokenId) internal {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(tokenId);
        uint256 tokensHash = _computeHash(token0, token1);
        deposits[tokensHash] = Deposit({
            depositType: DepositType.UNISWAPv3_LP, //TODO: fix hardcoding
            liquidity: liquidity,
            token0: token0,
            token1: token1,
            tokenId: tokenId
        });
        hashArray.push(tokensHash);
    }

    // to be used by frontend, creates a Deposit struct that will be turned into an actual position by the automation
    function orderNewUniswapV3LPDeposit(address token0, address token1)
        external
    {
        // compute hash
        uint256 tokensHash = _computeHash(token0, token1);

        // check that position doesn't already exist
        if (deposits[tokensHash].token0 == address(0)) {
            deposits[tokensHash] = Deposit({
                depositType: DepositType.UNISWAPv3_LP,
                liquidity: 0,
                token0: token0,
                token1: token1,
                tokenId: 0
            });
            hashArray.push(tokensHash);
        }
    }

    // To be used by frontend, removes a uni v3 lp position
    // Collects the fees associated with provided liquidity
    // The contract must hold the erc721 token before it can collect fees
    function removeUniswapV3LPDeposit(address _token0, address _token1)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // Caller must own the ERC721 position, meaning it must be a deposit

        // compute hash
        uint256 tokenHash = _computeHash(_token0, _token1);
        uint256 tokenId = deposits[tokenHash].tokenId;

        // check that position exists before removing liquidity
        if (deposits[tokenHash].token0 == _token0) {
            // set amount0Max and amount1Max to uint256.max to collect all fees
            // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
            INonfungiblePositionManager.CollectParams
                memory params = INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                });

            (amount0, amount1) = nonfungiblePositionManager.collect(params);

            // remove from mapping and hashArray
            delete (deposits[tokenHash]);
            // TODO: find way to safely remove hash from hashArray (find way to avoid unbounded gas)

            // send collected feed back to owner
            _sendToOwner(_token0, _token1, amount0, amount1);
        }
    }

    // Transfers funds to owner of NFT
    function _sendToOwner(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal {
        // send collected fees to owner
        TransferHelper.safeTransfer(token0, userAddress, amount0);
        TransferHelper.safeTransfer(token1, userAddress, amount1);
    }

    // to be used by frontend, creates a Deposit struct for a single swap DCA
    function orderNewTokenDeposit(address token0) external {
        // compute hash
        uint256 tokenHash = _computeHash(token0, address(0));

        // check that position doesn't already exist
        if (deposits[tokenHash].token0 == address(0)) {
            deposits[tokenHash] = Deposit({
                depositType: DepositType.TOKEN,
                liquidity: 0,
                token0: token0,
                token1: address(0),
                tokenId: 0
            });
            hashArray.push(tokenHash);
        }
    }

    // to be used by frontend, removes a uni v3 lp position
    function removeTokenDeposit(address token0) external {
        // compute hash
        uint256 tokenHash = _computeHash(token0, address(0));

        // check that position exists before removing liquidity
        if (deposits[tokenHash].token0 == token0) {
            // TODO: swap tokens back? or just transfer to user?

            // remove from mapping and hashArray
            delete (deposits[tokenHash]);
            // TODO: find way to safely remove hash from hashArray (find way to avoid unbounded gas)
        }
    }

    // mint the position on uniswap
    function mintNewPosition(
        uint256 amount0ToMint,
        uint256 amount1ToMint,
        address _token0,
        address _token1
    ) internal {
        // Approve the position manager
        TransferHelper.safeApprove(
            _token0,
            address(nonfungiblePositionManager),
            amount0ToMint
        );
        TransferHelper.safeApprove(
            _token1,
            address(nonfungiblePositionManager),
            amount1ToMint
        );

        // Get pool
        IUniswapV3Pool pool = IUniswapV3Pool(
            v3Factory.getPool(_token0, _token1, poolFee)
        );
        int24 tickSpacing = pool.tickSpacing();

        int24 lower = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 upper = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
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

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = nonfungiblePositionManager.mint(params);

        _createDeposit(tokenId);
    }

    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    ) internal {
        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
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

    function swapExactInputSingle(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) private returns (uint256 amountOut) {
        // Approve the router to spend first token
        TransferHelper.safeApprove(_tokenIn, address(swapRouter), _amountIn);

        uint32 secondsIn = 10;
        // TODO: _amountIn is a uint256 but the Uniswap function specifically takes a uint128. We should convert this or see if it's possible to pass in a uint256
        uint256 price = IUniswapV3PriceOracle(uniswapV3PriceOracle).estimateAmountOut(_tokenIn, uint128(_amountIn), secondsIn); // comment this out if needed

        // TODO: We need to use the price from the price oracle to calculate amountOutMinimum
        uint256 amountOutMinimum = 1;

        // Naively set amountOutMinimum to 0. In production, this value should be calculated using the Uniswap SDK 
        // or an onchain price oracle. This prevents losing funds from sandwich attacks and other forms of price manipulation
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: amountOutMinimum,
                sqrtPriceLimitX96: 0
            });

        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }

    function maintainUniswapV3LPPosition() internal {
        // swap downgraded tokens w/ tokens from liquidity pair
        address underlyingToken = acceptedToken.getUnderlyingToken();
        Deposit memory currentDeposit = deposits[hashArray[currentPosition]];
        uint256 underlyingContractBalance = IERC20(underlyingToken).balanceOf(
            address(this)
        );

        // TODO: use oralces to calculate the proper ratio of each asset (just going 50/50 here for testing)
        // assume here that if the streamed token is part of the pair, it should be token0
        if (underlyingToken == currentDeposit.token0) {
            swapExactInputSingle(
                underlyingToken,
                currentDeposit.token1,
                underlyingContractBalance
            );
        } else {
            swapExactInputSingle(
                underlyingToken,
                currentDeposit.token0,
                underlyingContractBalance / 2
            );
            swapExactInputSingle(
                underlyingToken,
                currentDeposit.token1,
                underlyingContractBalance / 2
            );
        }

        // get updated amounts of each token
        uint256 in1 = IERC20(currentDeposit.token0).balanceOf(address(this));
        uint256 in2 = IERC20(currentDeposit.token1).balanceOf(address(this));

        // only create/update position if balance of both tokens is > 0
        if (in1 > 0 && in2 > 0) {
            // either create a position or update an outstanding one
            if (currentDeposit.liquidity == 0) {
                mintNewPosition(
                    in1,
                    in2,
                    currentDeposit.token0,
                    currentDeposit.token1
                );
            } else {
                increaseLiquidityCurrentRange(currentDeposit.tokenId, in1, in2);
            }
        }
    }

    function maintainTokenPosition() internal {
        // swap all downgraded tokens with token0 of the deposit
        address underlyingToken = acceptedToken.getUnderlyingToken();
        Deposit memory currentDeposit = deposits[hashArray[currentPosition]];
        uint256 underlyingContractBalance = IERC20(underlyingToken).balanceOf(
            address(this)
        );

        swapExactInputSingle(
            underlyingToken,
            currentDeposit.token0,
            underlyingContractBalance
        );
    }

    function maintainPosition() external {
        downgradeToken();

        // get current deposit and perform action based on type (if a deposit exists / is queued)
        if (currentPosition < hashArray.length) {
            Deposit memory currentDeposit = deposits[
                hashArray[currentPosition]
            ];
            if (currentDeposit.depositType == DepositType.UNISWAPv3_LP) {
                maintainUniswapV3LPPosition();
            } else if (currentDeposit.depositType == DepositType.TOKEN) {
                maintainTokenPosition();
            }
        }

        // increment current position
        ++currentPosition;
        if (currentPosition >= hashArray.length) {
            currentPosition = 0;
        }
    }

    function downgradeToken() private {
        acceptedToken.downgrade(acceptedToken.balanceOf(address(this)));
    }
}
