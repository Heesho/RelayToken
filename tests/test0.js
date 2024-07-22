const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
const divDec = (amount, decimals = 18) => amount / 10 ** decimals;
const divDec6 = (amount, decimals = 6) => amount / 10 ** decimals;
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { execPath } = require("process");

const AddressZero = "0x0000000000000000000000000000000000000000";
const pointZeroOne = convert("0.01", 18);
const one = convert("1", 18);
const oneHundred = convert("100", 18);

const BASE_ADDR = "0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03";
const BERO_ADDR = "0xB5A27c33bA2ADEcee8CdBE94cEF5576E2F364A8f";
const OBERO_ADDR = "0x7629668774f918c00Eb4b03AdF5C4e2E53d45f0b";
const HIBERO_ADDR = "0x2B4141f98B8cD2a03F58bD722D4E8916d2106504";
const REWARDER_ADDR = "0xD6c2BE22e7b766c810690B22234044407dDa1C1B";
const VOTER_ADDR = "0x580ABF764405aA82dC96788b356435474c5956A7";
const MULTICALL_ADDR = "0x8452DA49f0ae4dA4392b5714C2F0096997c93fE7";

let owner, treasury, user0, user1, user2;
let relayFactory, tokenFactory, rewarderFactory, distroFactory, feeFlowFactory;
let relayToken, relayRewarder, relayDistro, relayFeeFlow;

describe("local: test0", function () {
  before("Initial set up", async function () {
    console.log("Begin Initialization");

    [owner, treasury, user0, user1, user2] = await ethers.getSigners();

    const relayFactoryArtifact = await ethers.getContractFactory(
      "RelayFactory"
    );
    relayFactory = await relayFactoryArtifact.deploy(
      BASE_ADDR,
      BERO_ADDR,
      OBERO_ADDR,
      HIBERO_ADDR,
      REWARDER_ADDR,
      VOTER_ADDR,
      MULTICALL_ADDR
    );
    console.log("- RelayFactory Initialized");

    const tokenFactoryArtifact = await ethers.getContractFactory(
      "RelayTokenFactory"
    );
    tokenFactory = await tokenFactoryArtifact.deploy(relayFactory.address);
    console.log("- TokenFactory Initialized");

    const rewarderFactoryArtifact = await ethers.getContractFactory(
      "RelayRewarderFactory"
    );
    rewarderFactory = await rewarderFactoryArtifact.deploy(
      relayFactory.address
    );
    console.log("- RewarderFactory Initialized");

    const distroFactoryArtifact = await ethers.getContractFactory(
      "RelayDistroFactory"
    );
    distroFactory = await distroFactoryArtifact.deploy(relayFactory.address);
    console.log("- DistroFactory Initialized");

    const feeFlowFactoryArtifact = await ethers.getContractFactory(
      "RelayFeeFlowFactory"
    );
    feeFlowFactory = await feeFlowFactoryArtifact.deploy(relayFactory.address);
    console.log("- FeeFlowFactory Initialized");

    await relayFactory.setRelayTokenFactory(tokenFactory.address);
    await relayFactory.setRelayRewarderFactory(rewarderFactory.address);
    await relayFactory.setRelayDistroFactory(distroFactory.address);
    await relayFactory.setRelayFeeFlowFactory(feeFlowFactory.address);
    console.log("- Factories Set");

    await relayFactory.createRelay(
      "RELAY",
      "RELAY",
      BASE_ADDR,
      oneHundred,
      one
    );
    console.log("- RELAY Token deployed");

    relayToken = await ethers.getContractAt(
      "RelayToken",
      await tokenFactory.lastRelayToken()
    );
    console.log("- relayToken Initialized");

    relayRewarder = await ethers.getContractAt(
      "RelayRewarder",
      await rewarderFactory.lastRelayRewarder()
    );
    console.log("- relayRewarder Initialized");

    relayDistro = await ethers.getContractAt(
      "RelayDistro",
      await distroFactory.lastRelayDistro()
    );
    console.log("- relayDistro Initialized");

    relayFeeFlow = await ethers.getContractAt(
      "RelayFeeFlow",
      await feeFlowFactory.lastRelayFeeFlow()
    );
    console.log("- relayFeeFlow Initialized");

    console.log("Initialization Complete");
    console.log();
  });

  it("First test", async function () {
    console.log("******************************************************");
  });
});
