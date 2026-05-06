import {ethers} from "hardhat";
import {expect} from "chai";
import {parseEther, ZeroAddress} from "ethers";
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";

describe("LidoPriceOracle", () => {
  let deployer: SignerWithAddress, gov: SignerWithAddress, alice: SignerWithAddress;
  let oracle: any, mockLido: any;

  async function deployFresh() {
    [deployer, gov, alice] = await ethers.getSigners();

    // Deploy a minimal mock that mimics ILidoStETH (identity mapping)
    const MockLidoStETH = await ethers.getContractFactory("MockILidoStETH");
    mockLido = await MockLidoStETH.deploy();

    const LidoPriceOracle = await ethers.getContractFactory("LidoPriceOracle");
    oracle = await LidoPriceOracle.deploy(mockLido.target);
  }

  beforeEach(async () => {
    await deployFresh();
  });

  it("deployment stores lido address", async () => {
    expect(await oracle.LIDO()).to.equal(mockLido.target);
  });

  it("reverts on zero address constructor", async () => {
    const LidoPriceOracle = await ethers.getContractFactory("LidoPriceOracle");
    await expect(LidoPriceOracle.deploy(ZeroAddress)).to.be.reverted;
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
