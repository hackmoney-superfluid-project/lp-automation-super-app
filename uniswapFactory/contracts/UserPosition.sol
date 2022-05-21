// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

// Provide liquidity contracts
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
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

contract UserPosition is KeeperCompatibleInterface, IERC721Receiver {
    /* --- Chain link --- */
    // Used to ensure that the upkeep is perfomed every __interval__ seconds
    uint256 public immutable interval;
    uint256 public lastTimeStamp;

    address public constant fDAI = 0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7;
    address public constant fDAIx = 0x745861AeD1EEe363b4AaA5F1994Be40b1e05Ff90;
    address public constant wrappedETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    uint24 public constant poolFee = 3000;

    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    ISwapRouter public immutable swapRouter;

    /// @notice Represents the deposit of an NFT
    struct Deposit {
        uint128 liquidity;
        address token0;
        address token1;
    }

    /// @dev deposits[tokenId] => Deposit
    mapping(uint256 => Deposit) public deposits;

    // the accepted super token
    ISuperToken acceptedToken;

    // owner address
    address userAddress;

    event PerformUpkeep(string message, uint256 timestamp);
    event Downgraded(string message, uint256 timestamp);
    event GetAmountToSwap(string message, uint256 amountToSwap, uint256 timestamp);
    event Swapped(string message, uint256 timestamp);
    event PosMinted(string message, uint256 timestamp, uint256 token);

    constructor(
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISuperToken _acceptedToken,
        address _userAddress,
        ISwapRouter _swapRouter) 
    {
        nonfungiblePositionManager = _nonfungiblePositionManager;
        acceptedToken = _acceptedToken;
        userAddress = _userAddress;
        swapRouter = _swapRouter;

        interval = 60;
        lastTimeStamp = block.timestamp;
    }
    
    // Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        // get position information

        _createDeposit(tokenId);

        return this.onERC721Received.selector;
    }

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

        // set the owner and data for position
        // operator is msg.sender
        deposits[tokenId] = Deposit({
            liquidity: liquidity,
            token0: token0,
            token1: token1
        });
    }

    /// @notice Calls the mint function defined in periphery, mints the same amount of each token.
    /// For this example we are providing 1000 DAI and 1000 wrappedETH in liquidity
    /// @return tokenId The id of the newly minted ERC721
    /// @return liquidity The amount of liquidity for the position
    /// @return amount0 The amount of token0
    /// @return amount1 The amount of token1
    function mintNewPosition(uint256 amount0ToMint, uint256 amount1ToMint, address _token0, address _token1)
        internal
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // transfer tokens to contract
        /*
        TransferHelper.safeTransferFrom(
            fDAI,
            msg.sender,
            address(this),
            amount0ToMint
        );
        TransferHelper.safeTransferFrom(
            wrappedETH,
            msg.sender,
            address(this),
            amount1ToMint
        );
        */

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

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: _token0,
                token1: _token1,
                fee: poolFee,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            });

        // Note that the pool defined by fDAI/wrappedETH and fee tier 0.3% must already be created and initialized in order to mint
        //nonfungiblePositionManager.mint(params);
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);

        // Create a deposit
        //_createDeposit(tokenId);

        // Remove allowance and refund in both assets.
        // Dont think we need this because refunded amounts will just stay in the contract
        /*
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(
                fDAI,
                address(nonfungiblePositionManager),
                0
            );
            uint256 refund0 = amount0ToMint - amount0;
            TransferHelper.safeTransfer(fDAI, msg.sender, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(
                wrappedETH,
                address(nonfungiblePositionManager),
                0
            );
            uint256 refund1 = amount1ToMint - amount1;
            TransferHelper.safeTransfer(wrappedETH, msg.sender, refund1);
        }
        */
    }

    /// @notice Collects the fees associated with provided liquidity
    /// @dev The contract must hold the erc721 token before it can collect fees
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collectAllFees(uint256 tokenId)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // Caller must own the ERC721 position, meaning it must be a deposit

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

        // send collected feed back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
    /// @param tokenId The id of the erc721 token
    /// @return amount0 The amount received back in token0
    /// @return amount1 The amount returned back in token1
    function decreaseLiquidityInHalf(uint256 tokenId)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        // caller must be the owner of the NFT
        require(msg.sender == userAddress, "Not the owner");
        // get liquidity data for tokenId
        uint128 liquidity = deposits[tokenId].liquidity;
        uint128 halfLiquidity = liquidity / 2;

        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        INonfungiblePositionManager.DecreaseLiquidityParams
            memory params = INonfungiblePositionManager
                .DecreaseLiquidityParams({
                    tokenId: tokenId,
                    liquidity: halfLiquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: block.timestamp
                });

        (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(
            params
        );

        //send liquidity back to owner
        _sendToOwner(tokenId, amount0, amount1);
    }

    /// @notice Increases liquidity in the current range
    /// @dev Pool must be initialized already to add liquidity
    /// @param tokenId The id of the erc721 token
    /// @param amount0 The amount to add of token0
    /// @param amount1 The amount to add of token1
    function increaseLiquidityCurrentRange(
        uint256 tokenId,
        uint256 amountAdd0,
        uint256 amountAdd1
    )
        external
        returns (
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        // Downgrade supertokens
        acceptedToken.downgrade(acceptedToken.balanceOf(address(this)));

        TransferHelper.safeTransferFrom(
            deposits[tokenId].token0,
            msg.sender,
            address(this),
            amountAdd0
        );
        TransferHelper.safeTransferFrom(
            deposits[tokenId].token1,
            msg.sender,
            address(this),
            amountAdd1
        );

        TransferHelper.safeApprove(
            deposits[tokenId].token0,
            address(nonfungiblePositionManager),
            amountAdd0
        );
        TransferHelper.safeApprove(
            deposits[tokenId].token1,
            address(nonfungiblePositionManager),
            amountAdd1
        );

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

        (liquidity, amount0, amount1) = nonfungiblePositionManager
            .increaseLiquidity(params);
    }

    /// @notice Transfers funds to owner of NFT
    /// @param tokenId The id of the erc721
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    function _sendToOwner(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1
    ) internal {
        // get owner of contract
        address owner = userAddress;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

    /// @notice Transfers the NFT to the owner
    /// @param tokenId The id of the erc721
    function retrieveNFT(uint256 tokenId) external {
        // must be the owner of the NFT
        require(msg.sender == userAddress, "Not the owner");
        // transfer ownership to original owner
        nonfungiblePositionManager.safeTransferFrom(
            address(this),
            msg.sender,
            tokenId
        );
        //remove information related to tokenId
        delete deposits[tokenId];
    }

    /// @notice swapExactInputSingle swaps a fixed amount of fDAI for a maximum possible amount of wrappedETH
    /// using the fDAI/wrappedETH 0.3% pool by calling `exactInputSingle` in the swap router.
    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its fDAI for this function to succeed.
    /// @param amountIn The exact amount of fDAI that will be swapped for wrappedETH.
    /// @return amountOut The amount of wrappedETH received.
    function swapExactInputSingle(address _tokenIn, uint256 amountIn) private returns (uint256 amountOut) {

        // Approve the router to spend fDAI.
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

    /// @notice swapExactOutputSingle swaps a minimum possible amount of fDAI for a fixed amount of wrappedETH.
    /// @dev The calling address must approve this contract to spend its fDAI for this function to succeed. As the amount of input fDAI is variable,
    /// the calling address will need to approve for a slightly higher amount, anticipating some variance.
    /// @param amountOut The exact amount of wrappedETH to receive from the swap.
    /// @param amountInMaximum The amount of fDAI we are willing to spend to receive the specified amount of wrappedETH.
    /// @return amountIn The amount of fDAI actually spent in the swap.
    function swapExactOutputSingle(uint256 amountOut, uint256 amountInMaximum) private returns (uint256 amountIn) {
        // Transfer the specified amount of fDAI to this contract.
        TransferHelper.safeTransferFrom(fDAI, address(this), address(this), amountInMaximum);

        // Approve the router to spend the specifed `amountInMaximum` of fDAI.
        // In production, you should choose the maximum amount to spend based on oracles or other data sources to acheive a better swap.
        TransferHelper.safeApprove(fDAI, address(swapRouter), amountInMaximum);

        ISwapRouter.ExactOutputSingleParams memory params =
            ISwapRouter.ExactOutputSingleParams({
                tokenIn: fDAI,
                tokenOut: wrappedETH,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMaximum,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        amountIn = swapRouter.exactOutputSingle(params);

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < amountInMaximum) {
            TransferHelper.safeApprove(fDAI, address(swapRouter), 0);
            TransferHelper.safeTransfer(fDAI, msg.sender, amountInMaximum - amountIn);
        }
    }

    /* --- Chainlink keeper required functions (https://docs.chain.link/docs/chainlink-keepers/compatible-contracts/) --- */
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        // Revalidate the check (perform this function every __interval__ seconds)
        //if ((block.timestamp - lastTimeStamp) > interval) {
            //lastTimeStamp = block.timestamp;

            emit PerformUpkeep('Entered performUpkeep function', block.timestamp);
            acceptedToken.downgrade(acceptedToken.balanceOf(address(this))); // reverting here? only issue w/ maticx, not fDAIx
            emit Downgraded('Downgraded token', block.timestamp);

            /*address ffDAIAddress = 0xd393b1E02dA9831Ff419e22eA105aAe4c47E1253;
            uint256 fDAIContractBalance = IERC20(ffDAIAddress).balanceOf(address(this));
            uint256 amountToSwap = fDAIContractBalance / 2;*/

            address underlyingToken = acceptedToken.getUnderlyingToken();
            uint256 underlyingContractBalance = IERC20(underlyingToken).balanceOf(address(this));
            uint256 amountToSwap = underlyingContractBalance / 2;
            emit GetAmountToSwap('Calculated amount to swap', amountToSwap, block.timestamp);

            uint256 amountSwapped = swapExactInputSingle(underlyingToken, amountToSwap);
            emit Swapped('Swapped tokens', block.timestamp);

            //(uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = mintNewPosition(amountToSwap, amountSwapped, underlyingToken, wrappedETH);
            uint256 amtIn1 = 0.000001 * (10 ** 18);
            uint256 amtIn2 = 0.000000000305729 * (10 ** 18);
            (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = mintNewPosition(amtIn1, amtIn2, underlyingToken, wrappedETH);
            emit PosMinted('Minted Position', block.timestamp, tokenId);
        //}
    }
}
