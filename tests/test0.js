const convert = (amount, decimals) => ethers.utils.parseUnits(amount, decimals);
const divDec = (amount, decimals = 18) => amount / 10 ** decimals;
const divDec6 = (amount, decimals = 6) => amount / 10 ** decimals;
const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const { execPath } = require("process");

const AddressZero = "0x0000000000000000000000000000000000000000";
const one = convert("1", 18);
const ten = convert("10", 18);
const oneHundred = convert("100", 18);

const HONEY_ADDR = "0x0E4aaF1351de4c0264C5c7056Ef3777b41BD8e03";
const BERO_ADDR = "0xB5A27c33bA2ADEcee8CdBE94cEF5576E2F364A8f";
const OBERO_ADDR = "0x7629668774f918c00Eb4b03AdF5C4e2E53d45f0b";
const HIBERO_ADDR = "0x2B4141f98B8cD2a03F58bD722D4E8916d2106504";
const REWARDER_ADDR = "0xD6c2BE22e7b766c810690B22234044407dDa1C1B";
const VOTER_ADDR = "0x580ABF764405aA82dC96788b356435474c5956A7";
const MULTICALL_ADDR = "0x8452DA49f0ae4dA4392b5714C2F0096997c93fE7";

const HONEY_HOLDER = "0x2e904b9aD200fB63F9f4eD96202524B0c26B494E";

// Standard ERC20 ABI
const ERC20_ABI = [
  "function balanceOf(address owner) view returns (uint256)",
  "function transfer(address to, uint amount) returns (bool)",
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function name() view returns (string)",
];

const BERO_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
  "function buy(uint256 amountBase, uint256 minToken, uint256 expireTimestamp, address toAccount, address provider) external returns (bool)",
];

let owner, treasury, user0, user1, user2;
let relayFactory, tokenFactory, rewarderFactory, distroFactory, feeFlowFactory;
let relayToken, relayRewarder, relayDistro, relayFeeFlow;
let HONEY, BERO;

describe("local: test0", function () {
  before("Initial set up", async function () {
    console.log("Begin Initialization");

    // Initialize provider
    provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
    await provider.ready; // Ensure the provider is connected

    [owner, treasury, user0, user1, user2] = await ethers.getSigners();

    HONEY = new ethers.Contract(HONEY_ADDR, ERC20_ABI, provider);
    console.log("- HONEY Initialized");

    BERO = new ethers.Contract(BERO_ADDR, BERO_ABI, provider);
    console.log("- BERO Initialized");

    const relayFactoryArtifact = await ethers.getContractFactory(
      "RelayFactory"
    );
    relayFactory = await relayFactoryArtifact.deploy(
      HONEY_ADDR,
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
      HONEY_ADDR,
      oneHundred,
      one
    );
    console.log("- RELAY Token deployed");

    relayToken = await ethers.getContractAt(
      "contracts/RelayTokenFactory.sol:RelayToken",
      await tokenFactory.connect(owner).lastRelayToken()
    );
    console.log("- relayToken Initialized at:", relayToken.address);

    relayRewarder = await ethers.getContractAt(
      "RelayRewarder",
      await rewarderFactory.connect(owner).lastRelayRewarder()
    );
    console.log("- relayRewarder Initialized");

    relayDistro = await ethers.getContractAt(
      "RelayDistro",
      await distroFactory.connect(owner).lastRelayDistro()
    );
    console.log("- relayDistro Initialized");

    relayFeeFlow = await ethers.getContractAt(
      "RelayFeeFlow",
      await feeFlowFactory.connect(owner).lastRelayFeeFlow()
    );
    console.log("- relayFeeFlow Initialized");

    console.log("Initialization Complete");
    console.log();
  });

  it("First Test", async function () {
    console.log("******************************************************");
  });

  it("Impersonate HONEY holder and send to user0", async function () {
    console.log("******************************************************");
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [HONEY_HOLDER],
    });
    const signer = ethers.provider.getSigner(HONEY_HOLDER);
    await owner.sendTransaction({
      to: HONEY_HOLDER,
      value: ethers.utils.parseEther("1"),
    });
    await HONEY.connect(signer).transfer(user0.address, oneHundred);
  });

  it("User0 Buys BERO with 10 HONEY", async function () {
    console.log("******************************************************");
    await HONEY.connect(user0).approve(BERO.address, ten);
    await BERO.connect(user0).buy(
      ten,
      1,
      1792282187,
      user0.address,
      AddressZero
    );
  });

  it("User0 mints relayToken with all TOKEN", async function () {
    console.log("******************************************************");
    console.log(relayToken.address);
    await BERO.connect(user0).approve(relayToken.address, ten);
    console.log(BERO.address);
    // console.log(await relayToken.connect(user0).balanceOf(user0.address));
    // await BERO.connect(user0).balanceOf(user0.address);
    await relayToken.connect(user0).mint(user0.address, one);
    // const code = await provider.getCode(BERO.address);
    // console.log("BERO code: ", code);
    // console.log(
    //   "User0 relayToken Balance: ",
    //   divDec(await relayToken.balanceOf(user0.address))
    // );
  });
});
