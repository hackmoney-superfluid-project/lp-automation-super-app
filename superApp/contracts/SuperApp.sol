//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

// import sub contract for user positions
//import "./UserPosition.sol";
import "./testContract.sol";

/* Uniswap required contracts */
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

//import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface KeeperCompatibleInterface {
    /**
     * @notice checks if the contract requires work to be done.
     * @param checkData data passed to the contract when checking for Upkeep.
     * @return upkeepNeeded boolean to indicate whether the keeper should call
     * performUpkeep or not.
     * @return performData bytes that the keeper should call performUpkeep with,
     * if upkeep is needed.
     */
    function checkUpkeep(bytes calldata checkData)
        external
        returns (bool upkeepNeeded, bytes memory performData);

    /**
     * @notice Performs work on the contract. Executed by the keepers, via the registry.
     * @param performData is the data which was passed back from the checkData
     * simulation.
     */
    function performUpkeep(bytes calldata performData) external;
}

interface IUniswapFactory {
    function createUserPositionContract(ISuperToken acceptedToken, address userAddress) external returns (address);
    function callPositionContract(address userAddress) external;
}

contract SuperAppPOC is KeeperCompatibleInterface, SuperAppBase {
    /* --- Chain link --- */
    // Used to ensure that the upkeep is perfomed every __interval__ seconds
    uint256 public immutable interval;
    uint256 public lastTimeStamp;

    /* --- Superfluid --- */
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;
    bytes32 public constant CFA_ID =
        keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    IConstantFlowAgreementV1 cfa;
    uint256 flowEndTime;
    ISuperToken private _acceptedToken;
    address public _receiver;
    address public daiAddress = 0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7;
    address public daixAddress = 0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f;
    mapping(address => mapping(address => uint256)) allowed;
    ISuperfluid _host;

    /* --- Uniswap --- */
    //INonfungiblePositionManager public immutable _nonfungiblePositionManager;

    /* --- Contract storage --- */
    // Track UserPosition contracts (map user address to contract address)
    mapping(address => address) public userPositions;
    address[] userArray;
    uint currUser;

    // Factory Contract
    IUniswapFactory factory;

    constructor(
        ISuperfluid host,
        ISuperToken acceptedToken,
        address uniswapFactoryAddress
    ) payable {
        assert(address(host) != address(0));
        assert(address(acceptedToken) != address(0));

        // uniswap
        currUser = 0;
        //_nonfungiblePositionManager = nonfungiblePositionManager;

        factory = IUniswapFactory(uniswapFactoryAddress);

        // chainlink vars
        interval = 10;
        lastTimeStamp = block.timestamp;

        _host = host;
        _acceptedToken = acceptedToken;
        //_receiver = '';

        cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(CFA_ID)));
        cfaV1 = CFAv1Library.InitData(host, cfa);

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP | // remove once added
            SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP; // remove once added

        host.registerApp(configWord);
    }

    function unwrap(ISuperToken _superToken) public {
        // TODO: move unwrapping to child contracts
        _superToken.downgrade(1);
    }

    function allowance(address owner, address delegate)
        public
        view
        returns (uint256)
    {
        return allowed[owner][delegate];
    }

    // need to approve the spend of ERC20 token
    function transfer(uint256 _amount) public {
        require(_amount > 0, "You need to sell at least some tokens");
        uint256 currentAllowance = IERC20(daiAddress).allowance(
            msg.sender,
            address(this)
        );
        require(currentAllowance >= _amount, "Check the token allowance");

        IERC20(daiAddress).transferFrom(address(this), _receiver, _amount);
    }

    function approve(address delegate, uint256 numTokens)
        public
        returns (bool)
    {
        allowed[msg.sender][delegate] = numTokens;
        return true;
    }

    /* --- Superfluid callbacks --- */
    event StreamInitiated(ISuperToken _superToken, string message, address newAddress);

    //onlyExpected(_superToken, _agreementClass)
    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, //_agreementId
        bytes calldata, //_agreementData
        bytes calldata, //_cbdata
        bytes calldata _ctx
    )
        external
        override
        onlyHost
        returns (bytes memory newCtx)
    {
        // get address of wallet that initiated stream (msg.sender would just point to this contract)
        ISuperfluid.Context memory decompiledContext = _host.decodeCtx(_ctx);
        (, int96 flowRate, , ) = cfa.getFlow(
            _superToken,
            decompiledContext.msgSender,
            address(this)
        );

        // create new UserPosition contract
        userPositions[decompiledContext.msgSender] = factory.createUserPositionContract(_superToken, decompiledContext.msgSender);
        userArray.push(decompiledContext.msgSender);

        // emit event
        emit StreamInitiated(_superToken, "Stream initiated successfully", userPositions[decompiledContext.msgSender]);

        // redirect stream to that contract and return new context
        // TODO: subtract fee from initial flow?
        newCtx = cfaV1.createFlowWithCtx(_ctx, userPositions[decompiledContext.msgSender], _superToken, flowRate);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData,
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {}

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        // TODO: remove UserPosition contract from map
        // TODO: do we close the position when stream ends? or we could just transfer the uniswap erc721 token to the user?

        if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass))
            return _ctx;
    }

    function _isSameToken(ISuperToken superToken) private view returns (bool) {
        return address(superToken) == address(_acceptedToken);
    }

    function _isCFAv1(address agreementClass) private view returns (bool) {
        return ISuperAgreement(agreementClass).agreementType() == CFA_ID;
    }

    modifier onlyHost() {
        require(
            msg.sender == address(cfaV1.host),
            "RedirectAll: support only one host"
        );
        _;
    }

    modifier onlyExpected(ISuperToken superToken, address agreementClass) {
        require(_isSameToken(superToken), "RedirectAll: not accepted token");
        require(_isCFAv1(agreementClass), "RedirectAll: only CFAv1 supported");
        _;
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
        if ((block.timestamp - lastTimeStamp) > interval) {
            lastTimeStamp = block.timestamp;
            factory.callPositionContract(userArray[currUser]);
            ++currUser;
            if(currUser >= userArray.length){
                currUser = 0;
            }
            
            // Get the next contract to maintain 
            // userArray[currUser] == user address for an existing 
        }
    }
}
