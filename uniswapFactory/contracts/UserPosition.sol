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

import "./IWMATIC.sol";
import '@openzeppelin/contracts/math/SafeMath.sol';

import "./ISuperToken.sol";
import "./ISETH.sol";
import "./KeeperCompatibleInterface.sol";
import "./IUniswapV3PriceOracle.sol";

//LiquidityManagement
contract UserPosition is IERC721Receiver {
    using SafeMath for uint256;

    /* --- Token Addresses --- */
    address public constant DAI = 0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735;
    address public constant fDAI = 0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7;
    address public constant fDAIx = 0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90;
    address public constant wrappedETH =
        0xc778417E063141139Fce010982780140Aa0cD5Ab;
    address public constant WMATIC = 0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889;
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
        uint128 liquidity;
        address token0;
        address token1;
        uint256 tokenId;
    }

    /* map hash (token0 + token1) to deposit */
    mapping(uint256 => Deposit) public deposits;
    /* store hashes (token0 + token1) for iteration over deposits mapping */
    uint256[] hashArray;
    /* map hash (token0 + token1) to index in hashArray for O(1) removal from hashArray */
    mapping(uint256 => uint256) public hashArrayIndices;
    /* the current index in the hashArray (for automation) */
    uint256 currentPosition = 0;

    /* --- Other Contract Storage --- */
    ISETH acceptedToken; // the accepted super token

    address userAddress; // owner address

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISETH _acceptedToken,
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
        pure
        returns (uint256)
    {
        return uint256(token0) + uint256(token1);
    }

    // gets number of deposits
    function getNumDeposits() public view returns (uint256) {
        return hashArray.length;
    }

    // gets amounts of each token in deposit
    function getDepositAmounts(address token0, address token1)
        public
        view
        returns (uint128 amount0, uint128 amount1)
    {
        // get token id
        uint256 tokensHash = _computeHash(token0, token1);
        uint256 tokenId = deposits[tokensHash].tokenId;

        // retrieve owed amounts
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = nonfungiblePositionManager.positions(tokenId);

        amount0 = tokensOwed0;
        amount1 = tokensOwed1;
    }

    // gets deposit for specific token pair
    function getDeposit(address token0, address token1)
        public
        view
        returns (Deposit memory)
    {
        uint256 hash = _computeHash(token0, token1);
        return deposits[hash];
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

        // we are just overwriting an existing deposit here
        deposits[tokensHash].liquidity = liquidity;
        deposits[tokensHash].token0 = token0;
        deposits[tokensHash].token1 = token1;
        deposits[tokensHash].tokenId = tokenId;
    }

    // helper method for ordering deposits
    function orderNewDeposit(
        DepositType depositType,
        address token0,
        address token1
    ) internal {
        // compute hash
        uint256 tokensHash = _computeHash(token0, token1);

        // check that position doesn't already exist
        if (deposits[tokensHash].token0 == address(0)) {
            // store new deposit in mapping and maintain circularly linked list
            deposits[tokensHash] = Deposit({
                depositType: depositType,
                liquidity: 0,
                token0: token0,
                token1: token1,
                tokenId: 0
            });

            // update hashArray and hashArrayIndices map
            hashArrayIndices[tokensHash] = hashArray.length;
            hashArray.push(tokensHash);
        }
    }

    // to be used by frontend, creates a Deposit struct that will be turned into an actual position by the automation
    function orderNewUniswapV3LPDeposit(address token0, address token1)
        external
    {
        orderNewDeposit(DepositType.UNISWAPv3_LP, token0, token1);
    }

    event collectionAmounts(uint256 amnt1, uint256 amnt2);

    // to be used both internally and externally, collects all fees for a given position
    function collectFees(
        address token0,
        address token1,
        bool sendToUser
    ) public returns (uint256 amount0, uint256 amount1) {
        // compute hash
        uint256 tokenHash = _computeHash(token0, token1);
        uint256 tokenId = deposits[tokenHash].tokenId;

        // check that position exists before trying to collect fees
        if (deposits[tokenHash].token0 == token0) {
            // set amount0Max and amount1Max to uint256.max to collect all fees
            // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
            INonfungiblePositionManager.CollectParams
                memory params = INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: sendToUser ? userAddress : address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                });

            (amount0, amount1) = nonfungiblePositionManager.collect(params);
            //emit collectionAmounts(amount0, amount1);
        }
    }

    // Helper function to remove specific index from the hashArray
    function _removeFromHashArray(uint256 index) internal {
        hashArray[index] = hashArray[hashArray.length - 1];
        hashArray.pop();
    }

    event reportInt(uint256 num);

    // To be used by frontend, removes a uni v3 lp position
    // Collects the fees associated with provided liquidity
    // The contract must hold the erc721 token before it can collect fees
    function removeUniswapV3LPDeposit(address token0, address token1)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // compute hash
        uint256 tokenHash = _computeHash(token0, token1);
        uint256 tokenId = deposits[tokenHash].tokenId;

        // check that position exists before removing liquidity
        if (deposits[tokenHash].token0 == token0) {
            // collect fees
            (uint256 amount0Fees, uint256 amount1Fees) = collectFees(
                token0,
                token1,
                false
            );

            // remove all liquidity
            // amount0Min and amount1Min are price slippage checks
            // if the amount received after burning is not greater than these minimums, transaction will fail
            // TODO: calculate appropriate values for amount0Min and amount1Min
            INonfungiblePositionManager.DecreaseLiquidityParams
                memory params = INonfungiblePositionManager
                    .DecreaseLiquidityParams({
                        tokenId: tokenId,
                        liquidity: (deposits[tokenHash].liquidity),
                        amount0Min: 0,
                        amount1Min: 0,
                        deadline: block.timestamp
                    });

            (
                uint256 amount0Liquidity,
                uint256 amount1Liquidity
            ) = nonfungiblePositionManager.decreaseLiquidity(params);

            // remove deposit from mapping and hashArray
            delete (deposits[tokenHash]);
            _removeFromHashArray(hashArrayIndices[tokenHash]);

            // send entire contract balance of each collected fees back to owner
            /*_sendToOwner(
                token0,
                token1,
                _getTokenBalance(token0),
                _getTokenBalance(token1)
            );*/

            emit collectionAmounts(
                _getTokenBalance(token0),
                _getTokenBalance(token1)
            );

            // swap token0 and token1 to accepted token and send back to user
            _swapAndSendToOwner(token0, _getTokenBalance(token0));
            _swapAndSendToOwner(token1, _getTokenBalance(token1));

            // return fees + liquidity
            amount0 = amount0Fees + amount0Liquidity;
            amount1 = amount1Fees + amount1Liquidity;

            emit collectionAmounts(
                _getTokenBalance(token0),
                _getTokenBalance(token1)
            );

            /*
            emit collectionAmounts(amount0, amount1);

            _sendToOwner(
                token0,
                token1,
                amount0,
                amount1
            );
            */
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

    // swaps back to acceptedToken and transfers back to owner
    function _swapAndSendToOwner(address token, uint256 amount) internal {
        if (amount > 0) {
            // get underlying token
            address underlyingToken = acceptedToken.getUnderlyingToken();

            // swap to underlying token of acceptedtoken (handle special case of matic underlying token)
            uint256 amountAfterSwap;
            if (underlyingToken == address(0)) {
                // swap with wmatic (if needed)
                if (token != WMATIC) {
                    amountAfterSwap = swapExactInputSingle(
                        token,
                        WMATIC,
                        amount
                    );
                } else {
                    amountAfterSwap = _getTokenBalance(token);
                }

                // downgrade to matic
                IWMATIC(WMATIC).withdraw(amountAfterSwap);
            } else {
                amountAfterSwap = swapExactInputSingle(
                    token,
                    underlyingToken,
                    amount
                );
            }
            emit reportInt(amountAfterSwap);

            // upgrade underlying tokens to super tokens (handle special case of matic underlying token)
            if (underlyingToken == address(0)) {
                acceptedToken.upgradeByETH{value: amountAfterSwap}();
            } else {
                acceptedToken.upgrade(amountAfterSwap);
            }

            // send collected fees to owner
            TransferHelper.safeTransfer(
                address(acceptedToken),
                userAddress,
                amountAfterSwap
            );
        }
    }

    // to be used by frontend, creates a Deposit struct for a single swap DCA
    function orderNewTokenDeposit(address token0) external {
        orderNewDeposit(DepositType.TOKEN, token0, address(0));
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
        emit collectionAmounts(amount0, amount1);

        _createDeposit(tokenId);
    }

    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amount0ToAdd,
        uint256 amount1ToAdd,
        address _token0,
        address _token1
    ) internal {
        // Approve the position manager
        TransferHelper.safeApprove(
            _token0,
            address(nonfungiblePositionManager),
            amount0ToAdd
        );
        TransferHelper.safeApprove(
            _token1,
            address(nonfungiblePositionManager),
            amount1ToAdd
        );

        INonfungiblePositionManager.IncreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amount0ToAdd,
                    amount1Desired: amount1ToAdd,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        nonfungiblePositionManager.increaseLiquidity(params);

        // this will overwrite the Deposit struct with updated data about the position
        _createDeposit(tokenId);
    }

    // helper function for getting balance of token
    function _getTokenBalance(address token)
        internal
        returns (uint256 balance)
    {
        if (token == address(0)) {
            balance = address(this).balance;
        } else {
            balance = IERC20(token).balanceOf(address(this));
        }
    }

    function swapExactInputSingle(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) private returns (uint256 amountOut) {
        // Approve the router to spend first token
        TransferHelper.safeApprove(_tokenIn, address(swapRouter), _amountIn);

        uint32 secondsIn = 10;
        uint256 price = IUniswapV3PriceOracle(uniswapV3PriceOracle).estimateAmountOut(
            _tokenIn,
            _tokenOut,
            uint128(_amountIn),
            secondsIn,
            poolFee
        );

        // we want no more than 1% slippage, so we are calculating 99% of the oracle price
        // TODO: Write a test for this calculation to ensure the desired output. See the following:
        // https://ethereum.stackexchange.com/questions/55701/how-to-do-solidity-percentage-calculation
        // Multiply before divide first to avoid rounding to zero. This can cause overflow issues though so maybe some more thought is required here
        uint256 amountOutMinimum = price.mul(99).div(100);

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

        // if underlyingToken is matic, wrap it and update the var
        if (underlyingToken == address(0)) {
            IWMATIC(WMATIC).deposit{value: address(this).balance}();
            underlyingToken = WMATIC;
        }

        Deposit memory currentDeposit = deposits[hashArray[currentPosition]];

        if (currentDeposit.token0 == address(0)) {
            currentDeposit.token0 = WMATIC;
        }

        uint256 underlyingContractBalance = _getTokenBalance(underlyingToken);

        // TODO: use oralces to calculate the proper ratio of each asset (just going 50/50 here for testing)
        // assume here that if the streamed token is part of the pair, it should be token0
        if (underlyingToken == currentDeposit.token0) {
            swapExactInputSingle(
                underlyingToken,
                currentDeposit.token1,
                underlyingContractBalance / 2 // (related to issue discovered on 6/14) TODO: find correct ratio here
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
        uint256 in1 = _getTokenBalance(currentDeposit.token0);
        uint256 in2 = _getTokenBalance(currentDeposit.token1);

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
                increaseLiquidityCurrentRange(
                    currentDeposit.tokenId,
                    in1,
                    in2,
                    currentDeposit.token0,
                    currentDeposit.token1
                );
            }
        }
    }

    function maintainTokenPosition() internal {
        // swap all downgraded tokens with token0 of the deposit
        address underlyingToken = acceptedToken.getUnderlyingToken();
        Deposit memory currentDeposit = deposits[hashArray[currentPosition]];
        uint256 underlyingContractBalance = _getTokenBalance(underlyingToken);

        swapExactInputSingle(
            underlyingToken,
            currentDeposit.token0,
            underlyingContractBalance
        );
    }

    // fix for MATICx downgrade
    receive() external payable {
        // do nothing here
    }

    function maintainPosition() external {
        // downgrade super tokens (use downgradeToETH if 0x0 address)
        if (acceptedToken.getUnderlyingToken() == address(0)) {
            acceptedToken.downgradeToETH(
                acceptedToken.balanceOf(address(this))
            );
        } else {
            acceptedToken.downgrade(acceptedToken.balanceOf(address(this)));
        }

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
