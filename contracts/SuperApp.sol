//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import { ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import { CFAv1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import { IConstantFlowAgreementV1 } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

interface IERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

contract SuperAppPOC is SuperAppBase {
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1;      
    bytes32 constant public CFA_ID = keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");

    ISuperToken private _acceptedToken;
    address public _receiver;  
    address public daiAddress = 0x15F0Ca26781C3852f8166eD2ebce5D18265cceb7;
    address public daixAddress = 0x5D8B4C2554aeB7e86F387B4d6c00Ac33499Ed01f;
    mapping(address => mapping (address => uint256)) allowed;

    constructor(
        ISuperfluid host,
        ISuperToken acceptedToken,
        address receiver
    ) payable {
        assert(address(host) != address(0));
        assert(address(acceptedToken) != address(0));
        assert(address(receiver) != address(0));

        _acceptedToken = acceptedToken;
        _receiver = receiver;

        cfaV1 = CFAv1Library.InitData(
            host,
            IConstantFlowAgreementV1(
                address(host.getAgreementClass(CFA_ID))
            )
        );

        uint256 configWord =
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP | // remove once added
            SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP; // remove once added

        host.registerApp(configWord);
    }

    function unwrap(ISuperToken _superToken) public {
        _superToken.downgrade(1);
    }


    function allowance(address owner, address delegate) public view returns (uint) {
        return allowed[owner][delegate];
    }

    // need to approve the spend of ERC20 token
    function transfer(uint256 _amount) public {
        require(_amount > 0, "You need to sell at least some tokens");
        uint256 currentAllowance = IERC20(daiAddress).allowance(msg.sender, address(this));
        require(currentAllowance >= _amount, "Check the token allowance");

        IERC20(daiAddress).transferFrom(address(this), _receiver, _amount);
    }

    function approve(address delegate, uint256 numTokens) public returns (bool) {
        allowed[msg.sender][delegate] = numTokens;
        return true;
    }



    event StreamInitiated(ISuperToken _superToken, string message);

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
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        emit StreamInitiated(_superToken, 'Stream initiated successfully');
        newCtx = _ctx;
    }

    // function afterAgreementUpdated(
    //     ISuperToken _superToken,
    //     address _agreementClass,
    //     bytes32, // _agreementId,
    //     bytes calldata, // _agreementData,
    //     bytes calldata, // _cbdata,
    //     bytes calldata _ctx
    // )
    //     external
    //     override
    //     onlyExpected(_superToken, _agreementClass)
    //     onlyHost
    //     returns (bytes memory newCtx)
    // {
    // }

    // function afterAgreementTerminated(
    //     ISuperToken _superToken,
    //     address _agreementClass,
    //     bytes32, // _agreementId,
    //     bytes calldata, // _agreementData
    //     bytes calldata, // _cbdata,
    //     bytes calldata _ctx
    // ) external override onlyHost returns (bytes memory newCtx) {
    //     if (!_isSameToken(_superToken) || !_isCFAv1(_agreementClass))
    //         return _ctx;
    // }

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
}


