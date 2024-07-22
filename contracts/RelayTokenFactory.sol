// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IVoter {
    function vote(address[] calldata plugins, uint256[] calldata weights) external;
    function claimBribes(address[] memory bribes) external;
}

interface IVTOKENRewarder {
    function getReward(address account) external;
}

interface IVTOKEN {
    function balanceOf(address account) external view returns (uint256);
    function deposit(uint256 amount) external;
    function burnFor(address account, uint256 amount) external;
}

interface ITOKEN {
    function getAccountCredit(address account) external view returns (uint256);
    function buy(uint256 amountBase, uint256 minToken, uint256 expireTimestamp, address toAccount, address provider) external;
    function borrow(uint256 amountBase) external;
}

interface IMulticall {
    function quoteBuyIn(uint256 input, uint256 slippageTolerance) external view returns (uint256 output, uint256 slippage, uint256 minOutput, uint256 autoMinOutput);
}

interface IBGT {
    function unboostedBalanceOf(address account) external view returns (uint256);
    function redeem(address receiver, uint256 amount) external;
}

interface IWBERA {
    function deposit() external payable;
}

interface IRelayFactory {
    function protocol() external view returns (address);
    function developer() external view returns (address);
    function base() external view returns (address);
    function token() external view returns (address);
    function oToken() external view returns (address);
    function vToken() external view returns (address);
    function vTokenRewarder() external view returns (address);
    function voter() external view returns (address);
    function multicall() external view returns (address);
}

contract RelayToken is ERC20, ERC20Permit, ERC20Votes, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*----------  CONSTANTS  --------------------------------------------*/

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DIVISOR = 10000;
    uint256 public constant ADMIN_FEE = 300;        // 3%
    uint256 public constant REWARDER_FEE = 1100;    // 11%
    uint256 public constant MAX_SLIPPAGE = 8000;    // 20% slippage

    address public constant BGT = 0xbDa130737BDd9618301681329bF2e46A016ff9Ad;
    address public constant WBERA = 0x7507c1dc16935B82698e4C63f2746A2fCf994dF8;

    /*----------  STATE VARIABLES  --------------------------------------*/

    address public immutable relayFactory;
    address public immutable base;
    address public immutable token;
    address public immutable oToken;
    address public immutable vToken;
    address public immutable vTokenRewarder;

    address public delegate;
    address public feeFlow;
    address public distro;

    address[] public plugins;
    uint256[] public weights;

    uint256 public slippageTolerance = 9500; // 5% slippage

    bool public mintable = true;

    /*----------  ERRORS ------------------------------------------------*/

    error RelayToken__InvalidZeroInput();
    error RelayToken__InvalidZeroAddress();
    error RelayToken__NotDelegate();
    error RelayToken__InvalidVote();
    error RelayToken__InvalidInput();
    error RelayToken__NotAdmin();
    error RelayToken__NotMintable();

    /*----------  EVENTS ------------------------------------------------*/

    event RelayToken__Mint(address indexed minter, address indexed account, uint256 amount);
    event RelayToken__Vote(address[] plugins, uint256[] weights);
    event RelayToken__ClaimBribes(address[] bribes);
    event RelayToken__SweepRewardTokens(address token);
    event RelayToken__ClaimVTokenRewards();
    event RelayToken__BurnOTokenForVToken(uint256 amount);
    event RelayToken__StakeTokenForVToken(uint256 amount);
    event RelayToken__BorrowBase(uint256 amount);
    event RelayToken__BuyTokenWithBase(uint256 amount);
    event RelayToken__Loop();
    event RelayToken__SetVotes(address[] plugins, uint256[] weights);
    event RelayToken__SetDelegate(address delegate);
    event RelayToken__SetFeeFlow(address feeFlow);
    event RelayToken__SetDistro(address distro);
    event RelayToken__SetSlippageTolerance(uint256 slippageTolerance);

    /*----------  MODIFIERS  --------------------------------------------*/

    modifier nonZeroInput(uint256 _amount) {
        if (_amount == 0) revert RelayToken__InvalidZeroInput();
        _;
    }

    modifier nonZeroAddress(address _account) {
        if (_account == address(0)) revert RelayToken__InvalidZeroAddress();
        _;
    }

    modifier onlyDelegate() {
        if (msg.sender != owner() && msg.sender != delegate) revert RelayToken__NotDelegate();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != owner() && msg.sender != relayFactory) revert RelayToken__NotAdmin();
        _;
    }

    /*----------  FUNCTIONS  --------------------------------------------*/

    constructor(
        address _relayFactory,
        address _owner,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
        ERC20Permit(_name)
    {
        relayFactory = _relayFactory;
        base = IRelayFactory(relayFactory).base();
        token = IRelayFactory(relayFactory).token();
        oToken = IRelayFactory(relayFactory).oToken();
        vToken = IRelayFactory(relayFactory).vToken();
        vTokenRewarder = IRelayFactory(relayFactory).vTokenRewarder();

        delegate = _owner;
        feeFlow = _owner;
        distro = _owner;
    }

    function mint(address account, uint256 amount) 
        external
        nonReentrant
        nonZeroInput(amount)
    {
        if (!mintable) revert RelayToken__NotMintable();
        _mint(account, amount);
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit RelayToken__Mint(msg.sender, account, amount);
    }

    function vote()
        external
    {
        address voter = IRelayFactory(relayFactory).voter();
        IVoter(voter).vote(plugins, weights);
        emit RelayToken__Vote(plugins, weights);
    }

    function claimBribes(address[] calldata bribes) 
        external
    {
        address voter = IRelayFactory(relayFactory).voter();
        IVoter(voter).claimBribes(bribes);
        emit RelayToken__ClaimBribes(bribes);
    }
    
    function sweepVotingRewards(address[] calldata tokens) 
        external
    {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != base && tokens[i] != token && tokens[i] != oToken && tokens[i] != vToken) {
                IERC20(tokens[i]).safeTransfer(feeFlow, IERC20(tokens[i]).balanceOf(address(this)));
                emit RelayToken__SweepRewardTokens(tokens[i]);
            }
        }
    }

    function sweepBgt() external {
        uint256 balance = IBGT(BGT).unboostedBalanceOf(address(this));
        IBGT(BGT).redeem(address(this), balance);
        IWBERA(WBERA).deposit{value: balance}();
        IERC20(WBERA).safeTransfer(feeFlow, IERC20(WBERA).balanceOf(address(this)));
    }

    function claimVTokenRewards() 
        public
    {
        IVTOKENRewarder(vTokenRewarder).getReward(address(this));
        emit RelayToken__ClaimVTokenRewards();
    }

    function burnOTokenForVToken() 
        public
    {
        uint256 balance = IERC20(oToken).balanceOf(address(this));
        if (balance > 0) {
            IERC20(oToken).safeApprove(vToken, 0);
            IERC20(oToken).safeApprove(vToken, balance);
            IVTOKEN(vToken).burnFor(address(this), balance);
            emit RelayToken__BurnOTokenForVToken(balance);
        }
    }

    function stakeTokenForVToken() 
        public
    {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeApprove(vToken, 0);
            IERC20(token).safeApprove(vToken, balance);
            IVTOKEN(vToken).deposit(balance);
            emit RelayToken__StakeTokenForVToken(balance);
        }
    }

    function borrowBase() 
        public
    {
        uint256 credit = ITOKEN(token).getAccountCredit(address(this));
        if (credit > 0) {
            ITOKEN(token).borrow(credit);
            emit RelayToken__BorrowBase(credit);
        }
    }

    function buyTokenWithBase(uint256 amountBase) 
        public
        nonZeroInput(amountBase)
    {

        uint256 adminFee = amountBase * ADMIN_FEE / DIVISOR;
        IERC20(base).safeTransfer(owner(), adminFee); // manager fee
        IERC20(base).safeTransfer(IRelayFactory(relayFactory).protocol(), adminFee); // protocol fee
        IERC20(base).safeTransfer(IRelayFactory(relayFactory).developer(), adminFee); // developer fee

        uint256 rewarderFee = amountBase * REWARDER_FEE / DIVISOR;
        IERC20(base).safeTransfer(distro, rewarderFee); // rewarder fee

        amountBase -= ((3 * adminFee) + rewarderFee);

        IERC20(base).safeApprove(token, 0);
        IERC20(base).safeApprove(token, amountBase);
        address multicall = IRelayFactory(relayFactory).multicall();
        (,,uint256 minOutput,) = IMulticall(multicall).quoteBuyIn(amountBase, slippageTolerance);
        ITOKEN(token).buy(amountBase, minOutput, block.timestamp + 1800, address(this), address(this));
        emit RelayToken__BuyTokenWithBase(amountBase);
    }

    function buyTokenWithMaxBase() 
        public
    {
        uint256 balance = IERC20(base).balanceOf(address(this));
        if (balance > 0) {
            buyTokenWithBase(balance);
        }
    }

    function loop(uint256 loops) 
        external 
    {
        for (uint256 i = 0; i < loops; i++) {
            claimVTokenRewards();
            burnOTokenForVToken();
            stakeTokenForVToken();
            borrowBase();
            buyTokenWithMaxBase();
            emit RelayToken__Loop();
        }
    }

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    function setVotes(address[] calldata _plugins, uint256[] calldata _weights) 
        external 
        onlyDelegate() 
    {
        if (_plugins.length != _weights.length) revert RelayToken__InvalidVote();
        plugins = _plugins;
        weights = _weights;
        emit RelayToken__SetVotes(_plugins, _weights);
    }

    function setDelegate(address _delegate) 
        external 
        onlyAdmin() 
        nonZeroAddress(_delegate) 
    {
        delegate = _delegate;
        emit RelayToken__SetDelegate(_delegate);
    }

    function setFeeFlow(address _feeFlow) 
        external 
        onlyAdmin() 
        nonZeroAddress(_feeFlow) 
    {
        feeFlow = _feeFlow;
        emit RelayToken__SetFeeFlow(_feeFlow);
    }

    function setDistro(address _distro) 
        external 
        onlyAdmin() 
        nonZeroAddress(_distro) 
    {
        distro = _distro;
        emit RelayToken__SetDistro(_distro);
    }

    function setSlippageTolerance(uint256 _slippageTolerance) 
        external 
        onlyAdmin() 
    {
        if (_slippageTolerance < MAX_SLIPPAGE) revert RelayToken__InvalidInput();
        slippageTolerance = _slippageTolerance;
        emit RelayToken__SetSlippageTolerance(_slippageTolerance);
    }

    function setMintable(bool _mintable) 
        external 
        onlyAdmin() 
    {
        mintable = _mintable;
    }

    /*----------  FUNCTION OVERRIDES  -----------------------------------*/

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20)
    {
        super._beforeTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(account, amount);
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    function getVote() 
        external 
        view 
        returns (address[] memory, uint256[] memory) 
    {
        return (plugins, weights);
    }

    function getLeverage() 
        external 
        view 
        returns (uint256) 
    {
        uint256 votingPower = IVTOKEN(vToken).balanceOf(address(this));
        return votingPower * PRECISION / totalSupply();
    }

}

contract RelayTokenFactory {

    address public relayFactory;
    address public lastRelayToken;

    error RelayTokenFactory__Unathorized();
    error RelayTokenFactory__InvalidZeroAddress();

    event RelayTokenFactory__RelayFactorySet(address indexed account);
    event RelayTokenFactory__RelayTokenCreated(address indexed relayToken);

    modifier onlyRelayFactory() {
        if (msg.sender != relayFactory) revert RelayTokenFactory__Unathorized();
        _;
    }

    constructor(address _relayFactory) {
        relayFactory = _relayFactory;
    }

    function setRelayFactory(address _relayFactory) external onlyRelayFactory {
        if (_relayFactory == address(0)) revert RelayTokenFactory__InvalidZeroAddress();
        relayFactory = _relayFactory;
        emit RelayTokenFactory__RelayFactorySet(_relayFactory);
    }

    function createRelayToken(address owner, string calldata name, string calldata symbol) external onlyRelayFactory returns (address) {
        RelayToken relayToken = new RelayToken(relayFactory, owner, name, symbol);
        relayToken.transferOwnership(owner);
        lastRelayToken = address(relayToken);
        emit RelayTokenFactory__RelayTokenCreated(lastRelayToken);
        return lastRelayToken;
    }
}