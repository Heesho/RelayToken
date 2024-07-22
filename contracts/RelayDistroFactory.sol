// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRelayRewarder {
    function notifyRewardAmount(address rewardToken, uint256 amount) external;
}

contract RelayDistro is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*----------  CONSTANTS  --------------------------------------------*/

    uint256 public constant DURATION = 7 days;

    /*----------  STATE VARIABLES  --------------------------------------*/

    address public relayFactory;
    address public relayRewarder;

    /*----------  FUNCTIONS  --------------------------------------------*/

    constructor(
        address _relayFactory,
        address _relayRewarder
    ) {
        relayFactory = _relayFactory;
        relayRewarder = _relayRewarder;
    }

    function distributeRewards(address[] calldata rewardTokens) external nonReentrant {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            uint256 balance = IERC20(rewardTokens[i]).balanceOf(address(this));
            if (balance > DURATION) {
                IERC20(rewardTokens[i]).safeApprove(relayRewarder, 0);
                IERC20(rewardTokens[i]).safeApprove(relayRewarder, balance);
                IRelayRewarder(relayRewarder).notifyRewardAmount(rewardTokens[i], balance);
            }
        }
    }

}

contract RelayDistroFactory {

    address public relayFactory;
    address public lastRelayDistro;

    error RelayDistroFactory__Unathorized();
    error RelayDistroFactory__InvalidZeroAddress();

    event RelayDistroFactory__RelayFactorySet(address indexed account);
    event RelayDistroFactory__RelayDistroCreated(address indexed relayToken);

    modifier onlyRelayFactory() {
        if (msg.sender != relayFactory) revert RelayDistroFactory__Unathorized();
        _;
    }

    constructor(address _relayFactory) {
        relayFactory = _relayFactory;
    }

    function setRelayFactory(address _relayFactory) external onlyRelayFactory {
        if (_relayFactory == address(0)) revert RelayDistroFactory__InvalidZeroAddress();
        relayFactory = _relayFactory;
        emit RelayDistroFactory__RelayFactorySet(_relayFactory);
    }

    function createRelayDistro(address owner, address relayRewarder) external onlyRelayFactory returns (address) {
        RelayDistro relayDistro = new RelayDistro(relayFactory, relayRewarder);
        relayDistro.transferOwnership(owner);
        lastRelayDistro = address(relayDistro);
        emit RelayDistroFactory__RelayDistroCreated(lastRelayDistro);
        return lastRelayDistro;
    }

}