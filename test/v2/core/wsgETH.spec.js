const {ethers} = require("hardhat");
const {expect} = require("chai");
const {parseEther, formatEther} = require("ethers/lib/utils");
const {time} = require("@nomicfoundation/hardhat-network-helpers");

describe.only("WsgETH.sol", () => {
  let sgEth, wsgEth, deployer, alice, multiSig;
  let MINTER_ROLE;

  beforeEach(async () => {
    const [owner, addr1, addr2] = await ethers.getSigners();

    const SgETH = await ethers.getContractFactory("SgETH");
    sgEth = await SgETH.deploy([]);
    await sgEth.deployed();

    deployer = owner;
    alice = addr1;
    multiSig = addr2;

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

    // approve sgEth to alice
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

    // approve sgEth to alice
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

  it("price per share", async () => {
    const splitterAddresses = [deployer.address, multiSig.address, wsgEth.address];
    const splitterValues = [6, 3, 31];

    const PaymentSplitter = await ethers.getContractFactory("PaymentSplitter");
    const paymentSplitter = await PaymentSplitter.deploy(splitterAddresses, splitterValues);
    await paymentSplitter.deployed();

    const rolloverVirtual = "1080000000000000000";
    const vETH2Addr = "0x898bad2774eb97cf6b94605677f43b41871410b1";

    const Withdrawals = await ethers.getContractFactory("Withdrawals");
    const withdrawals = await Withdrawals.deploy(vETH2Addr, rolloverVirtual);
    await withdrawals.deployed();

    const numValidators = 1000;
    const adminFee = 0;

    const addresses = [
      ethers.constants.AddressZero, // fee splitter
      sgEth.address, // sgETH address
      wsgEth.address, // wsgETH address
      multiSig.address, // government address
      ethers.constants.AddressZero, // deposit contract address - can't find deposit contract - using dummy address
    ];

    // add secondary minter contract / eoa
    const Minter = await ethers.getContractFactory("SharedDepositMinterV2");
    const minter = await Minter.deploy(numValidators, adminFee, addresses);
    await minter.deployed();

    const RewardsReceiver = await ethers.getContractFactory("RewardsReceiver");
    const rewardsReceiver = await RewardsReceiver.deploy(withdrawals.address, [
      sgEth.address,
      wsgEth.address,
      paymentSplitter.address,
      minter.address,
    ]);
    await rewardsReceiver.deployed();

    await sgEth.addMinter(minter.address);

    // approve sgEth to alice
    await sgEth.approve(wsgEth.address, parseEther("2"));
    await wsgEth.deposit(parseEther("2"), alice.address);

    await expect(wsgEth.connect(alice).redeem(parseEther("0.5"), alice.address, alice.address))
      .to.be.emit(wsgEth, "Withdraw")
      .withArgs(alice.address, alice.address, alice.address, parseEther("0.5"), parseEther("0.5"));

    // deposit to rewardReceiver to simulate reward
    await deployer.sendTransaction({
      to: rewardsReceiver.address,
      value: parseEther("1"),
    });
    // sends 60% of sgEth to WSGEth contract - so current rate is 1.5/2.1
    await rewardsReceiver.work();

    await expect(wsgEth.syncRewards()).to.be.revertedWith("SyncError()");
    // increase time by reward cycle
    await time.increase(24 * 60 * 60);
    await wsgEth.syncRewards();

    await time.increase(24 * 60 * 60);

    // redeem will get 1.1 sgEth
    await expect(wsgEth.connect(alice).redeem(parseEther("0.5"), alice.address, alice.address))
      .to.be.emit(wsgEth, "Withdraw")
      .withArgs(alice.address, alice.address, alice.address, parseEther("0.7"), parseEther("0.5"));
  });
});
