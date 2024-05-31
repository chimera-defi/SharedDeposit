const {ethers} = require("hardhat");
const {expect} = require("chai");
const {parseEther} = require("ethers/lib/utils");

describe("SharedDepositMinterV2", () => {
  let sgEth, paymentSplitter, minter, withdrawals, wsgEth, deployer, alice, multiSig;

  beforeEach(async () => {
    const [owner, addr1, addr2] = await ethers.getSigners();

    const SgETH = await ethers.getContractFactory("SgETH");
    sgEth = await SgETH.deploy([]);
    await sgEth.deployed();

    deployer = owner;
    alice = addr1;
    multiSig = addr2;

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

    const rolloverVirtual = "1080000000000000000";
    const vETH2Addr = "0x898bad2774eb97cf6b94605677f43b41871410b1";

    const Withdrawals = await ethers.getContractFactory("Withdrawals");
    withdrawals = await Withdrawals.deploy(vETH2Addr, rolloverVirtual);
    await withdrawals.deployed();

    const numValidators = 1000;
    const adminFee = 0;

    const FeeCalc = await ethers.getContractFactory("FeeCalc");
    const feeCalc = await FeeCalc.deploy(parseEther("0"), parseEther("0"));
    await feeCalc.deployed();

    const addresses = [
      feeCalc.address, // fee splitter
      sgEth.address, // sgETH address
      wsgEth.address, // wsgETH address
      multiSig.address, // government address
      ethers.constants.AddressZero, // deposit contract address - can't find deposit contract - using dummy address
    ];

    // add secondary minter contract / eoa
    const Minter = await ethers.getContractFactory("SharedDepositMinterV2");
    minter = await Minter.deploy(numValidators, adminFee, addresses);
    await minter.deployed();

    // const RewardsReceiver = await ethers.getContractFactory("RewardsReceiver");
    // rewardsReceiver = await RewardsReceiver.deploy(withdrawals.address, [
    //   sgEth.address,
    //   wsgEth.address,
    //   paymentSplitter.address,
    //   minter.address,
    // ]);
    // await rewardsReceiver.deployed();

    await sgEth.addMinter(minter.address);
  });

  it("deposit", async () => {
    const prevBalance = await sgEth.balanceOf(alice.address);
    await minter.connect(alice).deposit({
      value: parseEther("1"),
    });
    const afterBalance = await sgEth.balanceOf(alice.address);
    expect(afterBalance).to.eq(prevBalance.add(parseEther("1")));
  });

  it("depositFor", async () => {
    const prevBalance = await sgEth.balanceOf(alice.address);
    await minter.depositFor(alice.address, {
      value: parseEther("1"),
    });
    const afterBalance = await sgEth.balanceOf(alice.address);
    expect(afterBalance).to.eq(prevBalance.add(parseEther("1")));
  });

  it("depositAndStake", async () => {
    const prevStake = await wsgEth.maxRedeem(deployer.address);
    const prevBalance = await sgEth.balanceOf(wsgEth.address);
    await minter.depositAndStake({
      value: parseEther("1"),
    });
    const afterBalance = await sgEth.balanceOf(wsgEth.address);
    expect(afterBalance).to.eq(prevBalance.add(parseEther("1")));

    const afterStake = await wsgEth.maxRedeem(deployer.address);
    expect(afterStake).to.eq(prevStake.add(parseEther("1")));
  });

  it("depositAndStakeFor", async () => {
    const prevStake = await wsgEth.maxRedeem(alice.address);
    const prevBalance = await sgEth.balanceOf(wsgEth.address);
    await minter.depositAndStakeFor(alice.address, {
      value: parseEther("1"),
    });
    const afterBalance = await sgEth.balanceOf(wsgEth.address);
    expect(afterBalance).to.eq(prevBalance.add(parseEther("1")));

    const afterStake = await wsgEth.maxRedeem(alice.address);
    expect(afterStake).to.eq(prevStake.add(parseEther("1")));
  });

  it("withdraw, withdrawTo", async () => {
    await minter.connect(alice).deposit({
      value: parseEther("1"),
    });
    await expect(minter.connect(alice).withdraw(parseEther("1.1"))).to.be.revertedWith("");

    let prevBalance = await sgEth.balanceOf(alice.address);
    await minter.connect(alice).withdraw(parseEther("0.5"));
    let afterBalance = await sgEth.balanceOf(alice.address);

    expect(afterBalance).to.eq(prevBalance.sub(parseEther("0.5")));

    prevBalance = await sgEth.balanceOf(alice.address);
    await minter.connect(alice).withdrawTo(parseEther("0.5"), alice.address);
    afterBalance = await sgEth.balanceOf(alice.address);

    expect(afterBalance).to.eq(prevBalance.sub(parseEther("0.5")));
  });

  it("unstakeAndWithdraw", async () => {
    await minter.connect(alice).depositAndStake({
      value: parseEther("1"),
    });
    await expect(minter.connect(alice).unstakeAndWithdraw(parseEther("1.1"), alice.address)).to.be.revertedWith("");
    await expect(minter.connect(alice).unstakeAndWithdraw(parseEther("0.5"), alice.address)).to.be.revertedWith("");

    await wsgEth.connect(alice).approve(minter.address, ethers.constants.MaxUint256);
    let prevBalance = await wsgEth.balanceOf(alice.address);
    await minter.connect(alice).unstakeAndWithdraw(parseEther("0.5"), alice.address);
    let afterBalance = await wsgEth.balanceOf(alice.address);

    expect(afterBalance).to.eq(prevBalance.sub(parseEther("0.5")));
  });

  it("setWithdrawalCredential", async () => {
    const NOR_ROLE = await minter.NOR();
    await expect(minter.connect(alice).setWithdrawalCredential("0x")).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${NOR_ROLE}`,
    );

    await minter.setWithdrawalCredential("0x");
  });

  it("slash", async () => {
    const GOV_ROLE = await minter.GOV();
    await expect(minter.connect(alice).slash(parseEther("0.1"))).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
    );

    await expect(minter.connect(multiSig).slash(parseEther("0.1"))).to.be.revertedWith("AmountTooHigh()");

    await minter.connect(alice).depositAndStake({
      value: parseEther("10"),
    });
    await expect(minter.connect(multiSig).slash(parseEther("0.1")))
      .to.be.emit(sgEth, "Transfer")
      .withArgs(wsgEth.address, ethers.constants.AddressZero, parseEther("0.1"));
  });

  it("togglePause", async () => {
    const GOV_ROLE = await minter.GOV();
    await expect(minter.connect(alice).togglePause()).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
    );

    await expect(minter.connect(multiSig).togglePause()).to.be.emit(minter, "Paused").withArgs(multiSig.address);
  });

  it("migrateShares", async () => {
    const GOV_ROLE = await minter.GOV();
    await expect(minter.connect(alice).migrateShares(parseEther("0.1"))).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
    );

    await minter.connect(multiSig).migrateShares(parseEther("0.1"));
  });

  it("toggleWithdrawRefund", async () => {
    const GOV_ROLE = await minter.GOV();
    await expect(minter.connect(alice).toggleWithdrawRefund()).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
    );

    await minter.connect(multiSig).toggleWithdrawRefund();
  });

  it("setNumValidators", async () => {
    const GOV_ROLE = await minter.GOV();
    await expect(minter.connect(alice).setNumValidators(1)).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
    );
    await expect(minter.connect(multiSig).setNumValidators(0)).to.be.revertedWith("Minimum 1 validator");

    await minter.connect(multiSig).setNumValidators(1);
  });
});
