import {expect} from "chai";
import hh from "hardhat";
const {ethers} = hh;
import {parseEther} from "ethers";
import {time} from "@nomicfoundation/hardhat-network-helpers";

describe("SharedDepositMinterV2", () => {
  let sgEth, paymentSplitter, minter, withdrawals, wsgEth, rewardsReceiver, deployer, alice, bob, multiSig;

  beforeEach(async () => {
    const [owner, addr1, addr2, addr3] = await ethers.getSigners();

    const SgETH = await ethers.getContractFactory("SgETH");
    sgEth = await SgETH.deploy([]);
    await sgEth.waitForDeployment();
    sgEth.address = sgEth.target;

    deployer = owner;
    alice = addr1;
    bob = addr2;
    multiSig = addr3;

    // deploy sgeth
    const WSGETH = await ethers.getContractFactory("WSGETH");
    wsgEth = await WSGETH.deploy(sgEth.address, 24 * 60 * 60);
    await wsgEth.waitForDeployment();
    wsgEth.address = wsgEth.target;

    const splitterAddresses = [deployer.address, multiSig.address, wsgEth.address];
    const splitterValues = [6, 3, 31];

    const PaymentSplitter = await ethers.getContractFactory("PaymentSplitter");
    paymentSplitter = await PaymentSplitter.deploy(splitterAddresses, splitterValues);
    await paymentSplitter.waitForDeployment();
    paymentSplitter.address = paymentSplitter.target;

    const rolloverVirtual = "1080000000000000000";
    const vETH2Addr = "0x898bad2774eb97cf6b94605677f43b41871410b1";

    const Withdrawals = await ethers.getContractFactory("Withdrawals");
    withdrawals = await Withdrawals.deploy(vETH2Addr, rolloverVirtual);
    await withdrawals.waitForDeployment();
    withdrawals.address = withdrawals.target;

    const numValidators = 1000;
    const adminFee = 0;

    // const FeeCalc = await ethers.getContractFactory("FeeCalc");
    // const feeCalc = await FeeCalc.deploy(parseEther("0"), parseEther("0"));
    // await feeCalc.deployed();

    const addresses = [
      ethers.ZeroAddress,
      //feeCalc.address, // fee splitter
      sgEth.address, // sgETH address
      wsgEth.address, // wsgETH address
      multiSig.address, // government address
      ethers.ZeroAddress, // deposit contract address - can't find deposit contract - using dummy address
    ];

    // add secondary minter contract / eoa
    const Minter = await ethers.getContractFactory("SharedDepositMinterV2");
    minter = await Minter.deploy(numValidators, adminFee, addresses);
    await minter.waitForDeployment();
    minter.address = minter.target;

    const RewardsReceiver = await ethers.getContractFactory("RewardsReceiver");
    rewardsReceiver = await RewardsReceiver.deploy(withdrawals.address, [
      sgEth.address,
      wsgEth.address,
      paymentSplitter.address,
      minter.address,
    ]);
    await rewardsReceiver.waitForDeployment();
    rewardsReceiver.address = rewardsReceiver.target;

    await sgEth.addMinter(minter.address);
  });

  describe("functionality", () => {
    it("deposit", async () => {
      const prevBalance = await sgEth.balanceOf(alice.address);
      await minter.connect(alice).deposit({
        value: parseEther("1"),
      });
      const afterBalance = await sgEth.balanceOf(alice.address);
      expect(afterBalance).to.eq(prevBalance + (parseEther("1")));
    });

    it("depositFor", async () => {
      // alice deposit for bob
      const prevBalance = await sgEth.balanceOf(bob.address);
      await minter.connect(alice).depositFor(bob.address, {
        value: parseEther("1"),
      });
      const afterBalance = await sgEth.balanceOf(bob.address);
      expect(afterBalance).to.eq(prevBalance + (parseEther("1")));
    });

    it("depositAndStake", async () => {
      const prevStake = await wsgEth.maxRedeem(deployer.address);
      const prevBalance = await sgEth.balanceOf(wsgEth.address);
      await minter.depositAndStake({
        value: parseEther("1"),
      });
      const afterBalance = await sgEth.balanceOf(wsgEth.address);
      expect(afterBalance).to.eq(prevBalance + (parseEther("1")));

      const afterStake = await wsgEth.maxRedeem(deployer.address);
      expect(afterStake).to.eq(prevStake + (parseEther("1")));
    });

    it("depositAndStakeFor", async () => {
      // alice deposit and stake for bob
      const prevStake = await wsgEth.maxRedeem(bob.address);
      const prevBalance = await sgEth.balanceOf(wsgEth.address);
      await minter.connect(alice).depositAndStakeFor(bob.address, {
        value: parseEther("1"),
      });
      const afterBalance = await sgEth.balanceOf(wsgEth.address);
      expect(afterBalance).to.eq(prevBalance + (parseEther("1")));

      const afterStake = await wsgEth.maxRedeem(bob.address);
      expect(afterStake).to.eq(prevStake + (parseEther("1")));
    });

    it("withdraw, withdrawTo", async () => {
      await minter.connect(alice).deposit({
        value: parseEther("1"),
      });
      await expect(minter.connect(alice).withdraw(parseEther("1.1"))).to.be.revertedWith("ERC20: burn amount exceeds balance");

      let prevBalance = await sgEth.balanceOf(alice.address);
      await minter.connect(alice).withdraw(parseEther("0.5"));
      let afterBalance = await sgEth.balanceOf(alice.address);

      expect(afterBalance).to.eq(prevBalance - (parseEther("0.5")));

      prevBalance = await sgEth.balanceOf(alice.address);
      await minter.connect(alice).withdrawTo(parseEther("0.5"), bob.address);
      afterBalance = await sgEth.balanceOf(alice.address);

      expect(afterBalance).to.eq(prevBalance - (parseEther("0.5")));
    });

    it("unstakeAndWithdraw", async () => {
      await minter.connect(alice).depositAndStake({
        value: parseEther("1"),
      });
      await expect(minter.connect(alice).unstakeAndWithdraw(parseEther("1.1"), alice.address)).to.be.revertedWithPanic("0x11");
      await expect(minter.connect(alice).unstakeAndWithdraw(parseEther("0.5"), alice.address)).to.be.revertedWithPanic("0x11");

      await wsgEth.connect(alice).approve(minter.address, ethers.MaxUint256);
      let prevBalance = await wsgEth.balanceOf(alice.address);
      await minter.connect(alice).unstakeAndWithdraw(parseEther("0.5"), alice.address);
      let afterBalance = await wsgEth.balanceOf(alice.address);

      expect(afterBalance).to.eq(prevBalance - (parseEther("0.5")));
    });

    it("slash", async () => {
      await minter.connect(alice).depositAndStake({
        value: parseEther("10"),
      });
      expect(await wsgEth.maxWithdraw(alice.address)).to.eq(parseEther("10"));

      // deposit to rewardReceiver to simulate reward
      await deployer.sendTransaction({
        to: rewardsReceiver.address,
        value: parseEther("1"),
      });
      // sends 60% of sgEth to WSGEth contract
      await rewardsReceiver.work();

      // slash 0.1 eth from reward amount, so currently reward is 0.5
      await expect(minter.connect(multiSig).slash(parseEther("0.1")))
        .to.be.emit(sgEth, "Transfer")
        .withArgs(wsgEth.address, ethers.ZeroAddress, parseEther("0.1"));

      // max withdrawal amount is not changed yet because didn't called syncReward of WsgEth
      expect(await wsgEth.maxWithdraw(alice.address)).to.eq(parseEther("10"));

      await time.increase(24 * 60 * 60);

      // deposit more to call syncReward, rewards increases by linear from this moment
      await minter.connect(alice).depositAndStake({
        value: parseEther("1"),
      });

      await time.increase(24 * 60 * 60);

      // deposit more to call syncReward. can test with full reward
      await minter.connect(alice).depositAndStake({
        value: parseEther("1"),
      });

      // currently withdrawal amount is 10 + 1 + 1 + 0.6 - 0.1 = 12.5
      expect(await wsgEth.maxWithdraw(alice.address)).to.eq(parseEther("12.5"));
    });
  });

  describe("access control", async () => {
    it("setWithdrawalCredential", async () => {
      // only NOR Role can call this function
      const NOR_ROLE = await minter.NOR();
      await expect(minter.connect(alice).setWithdrawalCredential("0x")).to.be.revertedWith(
        `AccessControl: account ${alice.address.toLowerCase()} is missing role ${NOR_ROLE}`,
      );

      await minter.setWithdrawalCredential("0x");
    });

    it("slash", async () => {
      // only GOV Role can call this function
      const GOV_ROLE = await minter.GOV();
      await expect(minter.connect(alice).slash(parseEther("0.1"))).to.be.revertedWith(
        `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
      );

      await expect(minter.connect(multiSig).slash(parseEther("0.1"))).to.be.revertedWithCustomError(minter, "AmountTooHigh");

      await minter.connect(alice).depositAndStake({
        value: parseEther("10"),
      });
      await expect(minter.connect(multiSig).slash(parseEther("0.1")))
        .to.be.emit(sgEth, "Transfer")
        .withArgs(wsgEth.address, ethers.ZeroAddress, parseEther("0.1"));
    });

    it("togglePause", async () => {
      // only GOV Role can call this function
      const GOV_ROLE = await minter.GOV();
      await expect(minter.connect(alice).togglePause()).to.be.revertedWith(
        `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
      );

      await expect(minter.connect(multiSig).togglePause()).to.be.emit(minter, "Paused").withArgs(multiSig.address);
    });

    it("migrateShares", async () => {
      // only GOV Role can call this function
      const GOV_ROLE = await minter.GOV();
      await expect(minter.connect(alice).migrateShares(parseEther("0.1"))).to.be.revertedWith(
        `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
      );

      await minter.connect(multiSig).migrateShares(parseEther("0.1"));
    });

    it("toggleWithdrawRefund", async () => {
      // only GOV Role can call this function
      const GOV_ROLE = await minter.GOV();
      await expect(minter.connect(alice).toggleWithdrawRefund()).to.be.revertedWith(
        `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
      );

      await minter.connect(multiSig).toggleWithdrawRefund();
    });

    it("setNumValidators", async () => {
      // only GOV Role can call this function
      const GOV_ROLE = await minter.GOV();
      await expect(minter.connect(alice).setNumValidators(1)).to.be.revertedWith(
        `AccessControl: account ${alice.address.toLowerCase()} is missing role ${GOV_ROLE}`,
      );
      await expect(minter.connect(multiSig).setNumValidators(0)).to.be.revertedWithCustomError(minter, 'NoValidators');

      await minter.connect(multiSig).setNumValidators(1);
    });
  });
});
