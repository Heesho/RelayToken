// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IRelayTokenFactory {
    function createRelayToken(address owner, string calldata name, string calldata symbol) external returns (address);
}

interface IRelayRewarderFactory {
    function createRelayRewarder(address owner, address relayToken) external returns (address);
}

interface IRelayDistroFactory {
    function createRelayDistro(address owner, address relayRewarder) external returns (address);
}

interface IRelayFeeFlowFactory {
    function createRelayFeeFlow(address relayDistro, address rewardToken, uint256 initPrice, uint256 minInitPrice) external returns (address);
}

interface IRelayToken {
    function setDistro(address relayDistro) external;
    function setFeeFlow(address relayFeeFlow) external;
}

interface IRelayRewarder {
    function addReward(address rewardToken) external;
}

contract RelayFactory is Ownable {

    address public immutable base;
    address public immutable token;
    address public immutable oToken;
    address public immutable vToken;
    address public immutable vTokenRewarder;

    address public relayTokenFactory;
    address public relayRewarderFactory;
    address public relayDistroFactory;
    address public relayFeeFlowFactory;

    address public voter;
    address public multicall;
    address public protocol;
    address public developer;

    error RelayFactory__InvalidZeroAddress();
    error RelayFactory__Unauthorized();

    event RelayFactory__RelayCreated(string name, string symbol, address relayToken, address relayRewarder, address relayDistro, address relayFeeFlow);
    event RelayFactory__RelayTokenFactorySet(address relayTokenFactory);
    event RelayFactory__RelayRewarderFactorySet(address relayRewarderFactory);
    event RelayFactory__RelayDistroFactorySet(address relayDistroFactory);
    event RelayFactory__RelayFeeFlowFactorySet(address relayFeeFlowFactory);

    constructor(
        address _base, 
        address _token, 
        address _oToken, 
        address _vToken, 
        address _vTokenRewarder,
        address _voter,
        address _multicall
    ) {
        base = _base;
        token = _token;
        oToken = _oToken;
        vToken = _vToken;
        vTokenRewarder = _vTokenRewarder;
        voter = _voter;
        multicall = _multicall;
        protocol = msg.sender;
        developer = msg.sender;
    }

    function createRelay(string calldata name, string calldata symbol, address rewardToken, uint256 initPrice, uint256 minInitPrice) external returns (address relayToken, address relayRewarder, address relayDistro, address relayFeeFlow) {
        relayToken = IRelayTokenFactory(relayTokenFactory).createRelayToken(msg.sender, name, symbol);
        relayRewarder = IRelayRewarderFactory(relayRewarderFactory).createRelayRewarder(msg.sender, relayToken);
        relayDistro = IRelayDistroFactory(relayDistroFactory).createRelayDistro(msg.sender, relayRewarder);
        relayFeeFlow = IRelayFeeFlowFactory(relayFeeFlowFactory).createRelayFeeFlow(relayDistro, rewardToken, initPrice, minInitPrice);
        IRelayToken(relayToken).setDistro(relayDistro);
        IRelayToken(relayToken).setFeeFlow(relayFeeFlow);
        IRelayRewarder(relayRewarder).addReward(base);
        if (rewardToken != base) IRelayRewarder(relayRewarder).addReward(rewardToken);
        emit RelayFactory__RelayCreated(name, symbol, relayToken, relayRewarder, relayDistro, relayFeeFlow);
    }

    function setRelayTokenFactory(address _relayTokenFactory) external onlyOwner() {
        if (_relayTokenFactory == address(0)) revert RelayFactory__InvalidZeroAddress();
        relayTokenFactory = _relayTokenFactory;
        emit RelayFactory__RelayTokenFactorySet(_relayTokenFactory);
    }

    function setRelayRewarderFactory(address _relayRewarderFactory) external onlyOwner() {
        if (_relayRewarderFactory == address(0)) revert RelayFactory__InvalidZeroAddress();
        relayRewarderFactory = _relayRewarderFactory;
        emit RelayFactory__RelayRewarderFactorySet(_relayRewarderFactory);
    }

    function setRelayDistroFactory(address _relayDistroFactory) external onlyOwner() {
        if (_relayDistroFactory == address(0)) revert RelayFactory__InvalidZeroAddress();
        relayDistroFactory = _relayDistroFactory;
        emit RelayFactory__RelayDistroFactorySet(_relayDistroFactory);
    }

    function setRelayFeeFlowFactory(address _relayFeeFlowFactory) external onlyOwner() {
        if (_relayFeeFlowFactory == address(0)) revert RelayFactory__InvalidZeroAddress();
        relayFeeFlowFactory = _relayFeeFlowFactory;
        emit RelayFactory__RelayFeeFlowFactorySet(_relayFeeFlowFactory);
    }

    function setVoter(address _voter) external onlyOwner() {
        if (_voter == address(0)) revert RelayFactory__InvalidZeroAddress();
        voter = _voter;
    }

    function setMulticall(address _multicall) external onlyOwner() {
        if (_multicall == address(0)) revert RelayFactory__InvalidZeroAddress();
        multicall = _multicall;
    }

    function setProtocol(address _protocol) external onlyOwner() {
        if (_protocol == address(0)) revert RelayFactory__InvalidZeroAddress();
        protocol = _protocol;
    }

    function setDeveloper(address _developer) external {
        if (msg.sender != developer) revert RelayFactory__Unauthorized();
        if (_developer == address(0)) revert RelayFactory__InvalidZeroAddress();
        developer = _developer;
    }

    function addReward(address relayRewarder, address rewardToken) external onlyOwner() {
        IRelayRewarder(relayRewarder).addReward(rewardToken);
    }

}