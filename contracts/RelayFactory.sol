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

    event RelayFactory__RelayCreated(string name, string symbol, address indexed relayToken, address indexed relayTokenRewarder);
    event RelayFactory__RelayTokenFactorySet(address indexed relayTokenFactory);
    event RelayFactory__RelayRewarderFactorySet(address indexed relayRewarderFactory);
    event RelayFactory__RelayDistroFactorySet(address indexed relayDistroFactory);

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

    function createRelay(string calldata name, string calldata symbol, address rewardToken) external returns (address relayToken, address relayRewarder, address relayDistro) {
        relayToken = IRelayTokenFactory(relayTokenFactory).createRelayToken(msg.sender, name, symbol);
        relayRewarder = IRelayRewarderFactory(relayRewarderFactory).createRelayRewarder(msg.sender, relayToken);
        relayDistro = IRelayDistroFactory(relayDistroFactory).createRelayDistro(msg.sender, relayRewarder);
        // relayFeeFlow = IRelayFeeFlowFactory(relayFeeFlowFactory)
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

    function setRelayTreasuryFactory(address _relayTreasuryFactory) external onlyOwner() {
        if (_relayTreasuryFactory == address(0)) revert RelayFactory__InvalidZeroAddress();
        relayTreasuryFactory = _relayTreasuryFactory;
        emit RelayFactory__RelayTreasuryFactorySet(_relayTreasuryFactory);
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