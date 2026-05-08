import {ethers} from "hardhat";
import {expect} from "chai";
import {parseEther, ZeroAddress} from "ethers";
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";

describe("StEthPriceOracle", () => {
  let deployer: SignerWithAddress, gov: SignerWithAddress, alice: SignerWithAddress;
  let oracle: any, mockStEth: any;

  async function deployFresh() {
    [deployer, gov, alice] = await ethers.getSigners();

    // Deploy a minimal mock that mimics IStEth (identity mapping)
    const MockIStEth = await ethers.getContractFactory("MockIStEth");
    mockStEth = await MockIStEth.deploy();

    const StEthPriceOracle = await ethers.getContractFactory("StEthPriceOracle");
    oracle = await StEthPriceOracle.deploy(mockStEth.target);
  }

  beforeEach(async () => {
    await deployFresh();
  });

  it("deployment stores stETH address", async () => {
    expect(await oracle.ST_ETH()).to.equal(mockStEth.target);
  });

  it("reverts on zero address constructor", async () => {
    const StEthPriceOracle = await ethers.getContractFactory("StEthPriceOracle");
    await expect(StEthPriceOracle.deploy(ZeroAddress)).to.be.reverted;
  });

  it("getEthValue returns ETH value for LST amount", async () => {
    const ethValue = await oracle.getEthValue(parseEther("1"));
    // MockLSTPriceOracle returns identity by default (1:1)
    expect(ethValue).to.equal(parseEther("1"));
  });

  it("getLstValue returns LST value for ETH amount", async () => {
    const lstValue = await oracle.getLstValue(parseEther("1"));
    expect(lstValue).to.equal(parseEther("1"));
  });

  it("lastUpdated returns block.timestamp", async () => {
    const ts = await oracle.lastUpdated();
    const block = await ethers.provider.getBlock("latest");
    expect(ts).to.be.closeTo(block!.timestamp, 5);
  });

  it("round-trip consistency: getEthValue(getLstValue(x)) ≈ x", async () => {
    const amount = parseEther("100");
    const lst = await oracle.getLstValue(amount);
    const eth = await oracle.getEthValue(lst);
    // With identity oracle, should be exact
    expect(eth).to.equal(amount);
  });
});
