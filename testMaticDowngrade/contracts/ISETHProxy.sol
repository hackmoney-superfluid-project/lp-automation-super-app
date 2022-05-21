interface ISETHCustom {
    // using native token
    function upgradeByETH() external payable;
    function upgradeByETHTo(address to) external payable;
    function downgradeToETH(uint wad) external;

    // using wrapped native token
    function getUnderlyingToken() external view returns(address tokenAddr);
    function upgrade(uint256 amount) external;
    function upgradeTo(address to, uint256 amount, bytes calldata data) external;
    function downgrade(uint256 amount) external;
}

interface Proxy {

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback () external payable virtual;

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if call data
     * is empty.
     */
    receive () external payable virtual;
}

interface UUPSProxy is Proxy {

    /**
     * @dev Proxy initialization function.
     *      This should only be called once and it is permission-less.
     * @param initialAddress Initial logic contract code address to be used.
     */
    function initializeProxy(address initialAddress) external;
}

interface ISETHProxy is ISETHCustom, UUPSProxy {

    //function _implementation() internal override view returns (address);

    function upgradeByETH() external override payable;

    function upgradeByETHTo(address to) external override payable;

    function downgradeToETH(uint wad) external override;

    function getUnderlyingToken() external override view returns(address tokenAddr);

    function upgrade(uint wad) external override;

    function upgradeTo(address to, uint256 wad, bytes calldata data) external override;

    function downgrade(uint256 wad) external override;
}