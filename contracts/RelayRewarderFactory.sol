// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract RelayRewarder is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /*----------  CONSTANTS  --------------------------------------------*/

    uint256 public constant DURATION = 7 days;  // rewards are released over 7 days

    /*----------  STATE VARIABLES  --------------------------------------*/

    // struct to store reward data for each reward token
    struct Reward {
        uint256 periodFinish;           // timestamp when reward period ends
        uint256 rewardRate;             // reward rate per second
        uint256 lastUpdateTime;         // timestamp when reward data was last updated
        uint256 rewardPerTokenStored;   // reward per virtual token stored
    }

    address public immutable relayFactory;          // address of relay factory contract
    address public immutable relayToken;            // address of relay token contract

    mapping(address => Reward) public rewardData;   // reward token -> reward data
    mapping(address => bool) public isRewardToken;  // reward token -> true if reward token
    address[] public rewardTokens;                  // array of reward tokens

    mapping(address => mapping(address => uint256)) public userRewardPerTokenPaid;  // user -> reward token -> reward per virtual token paid
    mapping(address => mapping(address => uint256)) public rewards;                 // user -> reward token -> reward amount

    uint256 private _totalSupply;                   // total supply of virtual tokens
    mapping(address => uint256) private _balances;  // user -> virtual token balance

    /*----------  ERRORS ------------------------------------------------*/

    error RelayRewarder__NotAuthorizedUser();
    error RelayRewarder__NotRewardToken();
    error RelayRewarder__RewardTokenAlreadyAdded();
    error RelayRewarder__InvalidZeroInput();
    error RelayRewarder__NotAdmin();

    /*----------  EVENTS ------------------------------------------------*/

    event RelayRewarder__RewardAdded(address indexed rewardToken);
    event RelayRewarder__RewardNotified(address indexed rewardToken, uint256 reward);
    event RelayRewarder__Deposited(address indexed user, uint256 amount);
    event RelayRewarder__Withdrawn(address indexed user, uint256 amount);
    event RelayRewarder__RewardPaid(address indexed user, address indexed rewardsToken, uint256 reward);

    /*----------  MODIFIERS  --------------------------------------------*/

    modifier updateReward(address account) {
        for (uint i; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            rewardData[token].rewardPerTokenStored = rewardPerToken(token);
            rewardData[token].lastUpdateTime = lastTimeRewardApplicable(token);
            if (account != address(0)) {
                rewards[account][token] = earned(account, token);
                userRewardPerTokenPaid[account][token] = rewardData[token].rewardPerTokenStored;
            }
        }
        _;
    }

    modifier nonZeroInput(uint256 _amount) {
        if (_amount == 0) revert RelayRewarder__InvalidZeroInput();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != relayFactory && msg.sender != owner()) revert RelayRewarder__NotAdmin();
        _;
    }
    
    /*----------  FUNCTIONS  --------------------------------------------*/

    constructor(address _relayFactory, address _relayToken) {
        relayFactory = _relayFactory;
        relayToken = _relayToken;
    }

    /**
     * @notice Claim rewards accrued for an account. Claimed rewards are sent to the account.
     *         Can only be called by account or voter contract.
     * @param account The account to claim rewards for.
     */
    function getReward(address account) 
        external  
        updateReward(account) 
    {
        for (uint i; i < rewardTokens.length; i++) {
            address _rewardsToken = rewardTokens[i];
            uint256 reward = rewards[account][_rewardsToken];
            if (reward > 0) {
                rewards[account][_rewardsToken] = 0;
                emit RelayRewarder__RewardPaid(account, _rewardsToken, reward);
                IERC20(_rewardsToken).safeTransfer(account, reward);
            }
        }
    }

    /**
     * @notice Begin reward distribution to accounts with non-zero balances. Transfers tokens from msg.sender
     *         to this contract and begins accounting for distribution with new reward token rates. Only 
     *         the voter contract can call this function on existing reward tokens.
     * @param _rewardsToken the reward token to begin distribution for
     * @param reward the amount of reward tokens to distribute
     */
    function notifyRewardAmount(address _rewardsToken, uint256 reward) 
        external
        nonReentrant
        updateReward(address(0))
    {
        if (!isRewardToken[_rewardsToken]) revert RelayRewarder__NotRewardToken();

        IERC20(_rewardsToken).safeTransferFrom(msg.sender, address(this), reward);
        if (block.timestamp >= rewardData[_rewardsToken].periodFinish) {
            rewardData[_rewardsToken].rewardRate = reward / DURATION;
        } else {
            uint256 remaining = rewardData[_rewardsToken].periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardData[_rewardsToken].rewardRate;
            rewardData[_rewardsToken].rewardRate = (reward + leftover) / DURATION;
        }
        rewardData[_rewardsToken].lastUpdateTime = block.timestamp;
        rewardData[_rewardsToken].periodFinish = block.timestamp + DURATION;
        emit RelayRewarder__RewardNotified(_rewardsToken, reward);
    }

    function deposit(uint256 amount) 
        external 
        nonZeroInput(amount)
        updateReward(msg.sender)
    {
        _totalSupply = _totalSupply + amount;
        _balances[msg.sender] = _balances[msg.sender] + amount;
        emit RelayRewarder__Deposited(msg.sender, amount);
        IERC20(relayToken).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) 
        external 
        nonZeroInput(amount)
        updateReward(msg.sender) 
    {
        _totalSupply = _totalSupply - amount;
        _balances[msg.sender] = _balances[msg.sender] - amount;
        emit RelayRewarder__Withdrawn(msg.sender, amount);
        IERC20(relayToken).safeTransfer(msg.sender, amount);
    }

    /*----------  RESTRICTED FUNCTIONS  ---------------------------------*/

    /**
     * @notice Adds a reward token for distribution. Only voter contract can call this function.
     * @param _rewardsToken the reward token to add
     */
    function addReward(address _rewardsToken) 
        external 
        onlyAdmin()
    {
        if (isRewardToken[_rewardsToken]) revert RelayRewarder__RewardTokenAlreadyAdded();
        rewardTokens.push(_rewardsToken);
        isRewardToken[_rewardsToken] = true;
        emit RelayRewarder__RewardAdded(_rewardsToken);
    }

    /*----------  VIEW FUNCTIONS  ---------------------------------------*/

    function left(address rewardToken) external view returns (uint256) {
        if (block.timestamp >= rewardData[rewardToken].periodFinish) return 0;
        uint256 remaining = rewardData[rewardToken].periodFinish - block.timestamp;
        return remaining * rewardData[rewardToken].rewardRate;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable(address _rewardsToken) public view returns (uint256) {
        return Math.min(block.timestamp, rewardData[_rewardsToken].periodFinish);
    }

    function rewardPerToken(address _rewardsToken) public view returns (uint256) {
        if (_totalSupply == 0) return rewardData[_rewardsToken].rewardPerTokenStored;
        return
            rewardData[_rewardsToken].rewardPerTokenStored + ((lastTimeRewardApplicable(_rewardsToken) - rewardData[_rewardsToken].lastUpdateTime) 
            * rewardData[_rewardsToken].rewardRate * 1e18 / _totalSupply);
    }

    function earned(address account, address _rewardsToken) public view returns (uint256) {
        return 
            (_balances[account] * (rewardPerToken(_rewardsToken) - userRewardPerTokenPaid[account][_rewardsToken]) / 1e18) 
            + rewards[account][_rewardsToken];
    }

    function getRewardForDuration(address _rewardsToken) external view returns (uint256) {
        return rewardData[_rewardsToken].rewardRate * DURATION;
    }

}

contract RelayRewarderFactory {

    address public relayFactory;
    address public lastRelayRewarder;

    error RelayRewarderFactory__Unathorized();
    error RelayRewarderFactory__InvalidZeroAddress();

    event RelayRewarderFactory__RelayFactorySet(address indexed account);
    event RelayRewarderFactory__RelayRewarderCreated(address indexed relayRewarder);

    modifier onlyRelayFactory() {
        if (msg.sender != relayFactory) revert RelayRewarderFactory__Unathorized();
        _;
    }

    constructor(address _relayFactory) {
        relayFactory = _relayFactory;
    }

    function setRelayFactory(address _relayFactory) external onlyRelayFactory {
        if (_relayFactory == address(0)) revert RelayRewarderFactory__InvalidZeroAddress();
        relayFactory = _relayFactory;
        emit RelayRewarderFactory__RelayFactorySet(_relayFactory);
    }

    function createRelayRewarder(address owner, address relayToken) external onlyRelayFactory returns (address) {
        RelayRewarder relayRewarder = new RelayRewarder(relayFactory, relayToken);
        relayRewarder.transferOwnership(owner);
        lastRelayRewarder = address(relayRewarder);
        emit RelayRewarderFactory__RelayRewarderCreated(lastRelayRewarder);
        return lastRelayRewarder;
    }
}