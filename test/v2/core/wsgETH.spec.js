const {ethers} = require("hardhat");
const {expect} = require("chai");
const {parseEther} = require("ethers/lib/utils");

describe.only("WsgETH.sol", () => {
  let sgEth, wsgEth, deployer, alice;
  let MINTER_ROLE;

  beforeEach(async () => {
    const [owner, addr1] = await ethers.getSigners();

    const SgETH = await ethers.getContractFactory("SgETH");
    sgEth = await SgETH.deploy([]);
    await sgEth.deployed();

    deployer = owner;
    alice = addr1;

    MINTER_ROLE = await sgEth.MINTER();

    // deploy wsgeth
    const WSGETH = await ethers.getContractFactory("WSGETH");
    wsgEth = await WSGETH.deploy(sgEth.address, 24 * 60 * 60);
    await wsgEth.deployed();

    // mint tokens for test
    await sgEth.addMinter(deployer.address);
    await sgEth.mint(deployer.address, parseEther("1000"));
  });

  it("deposit", async () => {
    await expect(wsgEth.connect(alice).deposit(parseEther("1"), alice.address)).to.be.revertedWith(
      "TRANSFER_FROM_FAILED",
    );
    await expect(wsgEth.deposit(parseEther("1"), alice.address)).to.be.revertedWith("TRANSFER_FROM_FAILED");

    await sgEth.approve(wsgEth.address, parseEther("1"));
    await expect(wsgEth.deposit(parseEther("1"), alice.address))
      .to.be.emit(wsgEth, "Transfer")
      .withArgs(ethers.constants.AddressZero, alice.address, parseEther("1"));
  });

  it("mint", async () => {
    await expect(wsgEth.connect(alice).mint(parseEther("1"), alice.address)).to.be.revertedWith("TRANSFER_FROM_FAILED");
    await expect(wsgEth.mint(parseEther("1"), alice.address)).to.be.revertedWith("TRANSFER_FROM_FAILED");

    await sgEth.approve(wsgEth.address, parseEther("1"));
    await expect(wsgEth.mint(parseEther("1"), alice.address))
      .to.be.emit(wsgEth, "Transfer")
      .withArgs(ethers.constants.AddressZero, alice.address, parseEther("1"));
  });

  it("withdraw", async () => {
    await expect(wsgEth.withdraw(parseEther("1"), alice.address, alice.address)).to.be.revertedWith(""); // panic revert by insufficient allowance
    await wsgEth.connect(alice).approve(deployer.address, parseEther("1000"));

    await expect(wsgEth.withdraw(parseEther("1"), alice.address, alice.address)).to.be.revertedWith(""); // panic revert by insufficient balance

    // mint wsgEth to alice
    await sgEth.approve(wsgEth.address, parseEther("1"));
    await wsgEth.deposit(parseEther("1"), alice.address);

    await expect(wsgEth.withdraw(parseEther("1"), alice.address, alice.address))
      .to.be.emit(wsgEth, "Withdraw")
      .withArgs(deployer.address, alice.address, alice.address, parseEther("1"), parseEther("1"));
  });

  it("redeem", async () => {
    await expect(wsgEth.redeem(parseEther("1"), alice.address, alice.address)).to.be.revertedWith(""); // panic revert by insufficient allowance
    await wsgEth.connect(alice).approve(deployer.address, parseEther("1000"));

    await expect(wsgEth.redeem(parseEther("1"), alice.address, alice.address)).to.be.revertedWith(""); // panic revert by insufficient balance

    // mint wsgEth to alice
    await sgEth.approve(wsgEth.address, parseEther("1"));
    await wsgEth.deposit(parseEther("1"), alice.address);

    await expect(wsgEth.redeem(parseEther("1"), alice.address, alice.address))
      .to.be.emit(wsgEth, "Withdraw")
      .withArgs(deployer.address, alice.address, alice.address, parseEther("1"), parseEther("1"));
  });

  it("depositWithSignature", async () => {
    await sgEth.transfer(alice.address, parseEther("1"));
    const nonce = await sgEth.nonces(alice.address);
    const deadline = Math.floor(Date.now() / 1000) + 1000;
    const approveData = {
      owner: alice.address,
      spender: wsgEth.address,
      value: parseEther("1"),
      nonce,
      deadline: deadline,
    };

    const domain = await sgEth.eip712Domain();

    const signature = await alice._signTypedData(
      {
        name: domain.name,
        version: domain.version,
        chainId: domain.chainId,
        verifyingContract: domain.verifyingContract,
      },
      {
        Permit: [
          {name: "owner", type: "address"},
          {name: "spender", type: "address"},
          {name: "value", type: "uint256"},
          {name: "nonce", type: "uint256"},
          {name: "deadline", type: "uint256"},
        ],
      },
      approveData,
    );

    const {r, s, v} = ethers.utils.splitSignature(signature);

    await expect(wsgEth.connect(alice).depositWithSignature(parseEther("1"), alice.address, deadline, false, v, r, s))
      .to.be.emit(wsgEth, "Transfer")
      .withArgs(ethers.constants.AddressZero, alice.address, parseEther("1"));
  });
});
