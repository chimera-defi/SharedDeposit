const {ethers} = require("hardhat");
const {expect} = require("chai");
const {parseEther} = require("ethers/lib/utils");
const {time} = require("@nomicfoundation/hardhat-network-helpers");

describe("WithdrawalQueue", () => {
  let sgEth, paymentSplitter, minter, withdrawalQueue, wsgEth, rewardsReceiver, deployer, alice, bob, multiSig;

  beforeEach(async () => {
    const [owner, addr1, addr2, addr3] = await ethers.getSigners();

    const SgETH = await ethers.getContractFactory("SgETH");
    sgEth = await SgETH.deploy([]);
    await sgEth.deployed();

    deployer = owner;
    alice = addr1;
    bob = addr2;
    multiSig = addr3;

    MINTER_ROLE = await sgEth.MINTER();

    // deploy sgeth
    const WSGETH = await ethers.getContractFactory("WSGETH");
    wsgEth = await WSGETH.deploy(sgEth.address, 24 * 60 * 60);
    await wsgEth.deployed();

    const splitterAddresses = [deployer.address, multiSig.address, wsgEth.address];
    const splitterValues = [6, 3, 31];

    const PaymentSplitter = await ethers.getContractFactory("PaymentSplitter");
    paymentSplitter = await PaymentSplitter.deploy(splitterAddresses, splitterValues);
    await paymentSplitter.deployed();

    const numValidators = 1000;
    const adminFee = 0;

    // const FeeCalc = await ethers.getContractFactory("FeeCalc");
    // const feeCalc = await FeeCalc.deploy(parseEther("0"), parseEther("0"));
    // await feeCalc.deployed();

    const addresses = [
      ethers.constants.AddressZero,
      //feeCalc.address, // fee splitter
      sgEth.address, // sgETH address
      wsgEth.address, // wsgETH address
      multiSig.address, // government address
      ethers.constants.AddressZero, // deposit contract address - can't find deposit contract - using dummy address
    ];

    // add secondary minter contract / eoa
    const Minter = await ethers.getContractFactory("SharedDepositMinterV2");
    minter = await Minter.deploy(numValidators, adminFee, addresses);
    await minter.deployed();

    const WithdrawalQueue = await ethers.getContractFactory("WithdrawalQueue");
    withdrawalQueue = await WithdrawalQueue.deploy(minter.address, wsgEth.address);
    await withdrawalQueue.deployed();

    const RewardsReceiver = await ethers.getContractFactory("RewardsReceiver");
    rewardsReceiver = await RewardsReceiver.deploy(withdrawalQueue.address, [
      sgEth.address,
      wsgEth.address,
      paymentSplitter.address,
      minter.address,
    ]);
    await rewardsReceiver.deployed();

    await sgEth.addMinter(minter.address);

    // prepare for test
    await minter.connect(alice).depositAndStake({
      value: parseEther("50"),
    });
    await minter.connect(bob).depositAndStake({
      value: parseEther("50"),
    });
    await wsgEth.connect(alice).approve(withdrawalQueue.address, parseEther("50"));
    await wsgEth.connect(bob).approve(withdrawalQueue.address, parseEther("50"));
    // sends some eth to withdrawal queue contract for test
    await deployer.sendTransaction({
      to: withdrawalQueue.address,
      value: parseEther("10"),
    });
  });

  it("request redeem(total request amount is less than 32 ether)", async () => {
    await expect(withdrawalQueue.connect(alice).requestRedeem(0, alice.address, alice.address)).to.be.revertedWith(
      "InvalidAmount()",
    );

    await expect(withdrawalQueue.connect(alice).requestRedeem(parseEther("1"), alice.address, alice.address))
      .to.be.emit(withdrawalQueue, "RedeemRequest")
      .withArgs(alice.address, alice.address, 0, alice.address, parseEther("1"));

    expect(await withdrawalQueue.pendingRedeemRequest(alice.address)).to.eq(parseEther("1"));
  });

  it("request redeem(total request amount is less than 32 ether) from another operator(operator functionality check)", async () => {
    await expect(
      withdrawalQueue.connect(alice).requestRedeem(parseEther("1"), alice.address, bob.address),
    ).to.be.revertedWith("PermissionDenied()");

    await expect(withdrawalQueue.connect(bob).setOperator(alice.address, true))
      .to.be.emit(withdrawalQueue, "OperatorSet")
      .withArgs(bob.address, alice.address, true);

    await expect(withdrawalQueue.connect(alice).requestRedeem(parseEther("1"), alice.address, bob.address))
      .to.be.emit(withdrawalQueue, "RedeemRequest")
      .withArgs(alice.address, bob.address, 0, alice.address, parseEther("1"));
    expect(await withdrawalQueue.pendingRedeemRequest(alice.address)).to.eq(parseEther("1"));
  });

  it("request redeem(total request amount is bigger than 32 ether)", async () => {
    await expect(withdrawalQueue.connect(alice).requestRedeem(parseEther("10"), alice.address, alice.address))
      .to.be.emit(withdrawalQueue, "RedeemRequest")
      .withArgs(alice.address, alice.address, 0, alice.address, parseEther("10"));
    await expect(withdrawalQueue.connect(bob).requestRedeem(parseEther("30"), bob.address, bob.address))
      .to.be.emit(withdrawalQueue, "RedeemRequest")
      .withArgs(bob.address, bob.address, 1, bob.address, parseEther("30"));

    expect(await withdrawalQueue.pendingRedeemRequest(alice.address)).to.eq(0);
    expect(await withdrawalQueue.pendingRedeemRequest(bob.address)).to.eq(0);
    expect(await withdrawalQueue.claimableRedeemRequest(alice.address)).to.eq(parseEther("10"));
    expect(await withdrawalQueue.claimableRedeemRequest(bob.address)).to.eq(parseEther("30"));
  });

  it("redeem(amount is less than queue balance)", async () => {
    await expect(withdrawalQueue.connect(alice).requestRedeem(parseEther("10"), alice.address, alice.address))
      .to.be.emit(withdrawalQueue, "RedeemRequest")
      .withArgs(alice.address, alice.address, 0, alice.address, parseEther("10"));
    await expect(withdrawalQueue.connect(bob).requestRedeem(parseEther("30"), bob.address, bob.address))
      .to.be.emit(withdrawalQueue, "RedeemRequest")
      .withArgs(bob.address, bob.address, 1, bob.address, parseEther("30"));

    const prevBalance = await deployer.provider.getBalance(withdrawalQueue.address);
    await expect(
      withdrawalQueue.connect(alice).redeem(parseEther("50"), alice.address, alice.address),
    ).to.be.revertedWith(""); // reverted from panic error
    await expect(withdrawalQueue.connect(alice).redeem(parseEther("5"), alice.address, alice.address))
      .to.emit(withdrawalQueue, "Redeem")
      .withArgs(alice.address, alice.address, parseEther("5"), parseEther("5"));
    const afterBalance = await deployer.provider.getBalance(withdrawalQueue.address);

    expect(prevBalance.sub(afterBalance)).to.eq(parseEther("5"));
  });

  it("redeem(amount is bigger than queue balance)", async () => {
    await expect(withdrawalQueue.connect(alice).requestRedeem(parseEther("10"), alice.address, alice.address))
      .to.be.emit(withdrawalQueue, "RedeemRequest")
      .withArgs(alice.address, alice.address, 0, alice.address, parseEther("10"));
    await expect(withdrawalQueue.connect(bob).requestRedeem(parseEther("30"), bob.address, bob.address))
      .to.be.emit(withdrawalQueue, "RedeemRequest")
      .withArgs(bob.address, bob.address, 1, bob.address, parseEther("30"));

    const prevBalance = await deployer.provider.getBalance(minter.address);
    await expect(withdrawalQueue.connect(bob).redeem(parseEther("20"), bob.address, bob.address))
      .to.emit(withdrawalQueue, "Redeem")
      .withArgs(bob.address, bob.address, parseEther("20"), parseEther("20"));
    const afterBalance = await deployer.provider.getBalance(minter.address);
    const queueAfterBalance = await deployer.provider.getBalance(withdrawalQueue.address);

    // 20 - 10 = 10
    expect(prevBalance.sub(afterBalance)).to.eq(parseEther("10"));
    // 10 - 10 = 0
    expect(queueAfterBalance).to.eq(0);
  });
});
