import {expect} from "chai";
import hh from "hardhat";
const {ethers} = hh;
import {parseEther} from "ethers";

describe("RewardsReceiver", () => {
  let rewardsReceiver, sgEth, paymentSplitter, minter, withdrawals, wsgEth, deployer, alice, multiSig;

  beforeEach(async () => {
    const [owner, addr1, addr2] = await ethers.getSigners();

    const SgETH = await ethers.getContractFactory("SgETH");
    sgEth = await SgETH.deploy([]);
    await sgEth.waitForDeployment();
    sgEth.address = sgEth.target;

    deployer = owner;
    alice = addr1;
    multiSig = addr2;

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
    // const feeCalc = await FeeCalc.deploy(parseEther("0.1"), parseEther("0.1"));
    // await feeCalc.deployed();

    const addresses = [
      ethers.ZeroAddress,
      // feeCalc.address, // fee splitter
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

  it("work", async () => {
    // deposit eth for test
    await deployer.sendTransaction({
      to: rewardsReceiver.address,
      value: parseEther("1"),
    });

    let prevBalance = await deployer.provider.getBalance(rewardsReceiver.address);
    await rewardsReceiver.work();
    let afterBalance = await deployer.provider.getBalance(rewardsReceiver.address);
    expect(afterBalance).to.eq(prevBalance - (parseEther("1")));

    await deployer.sendTransaction({
      to: rewardsReceiver.address,
      value: parseEther("1"),
    });
    await rewardsReceiver.flipState();

    prevBalance = await deployer.provider.getBalance(rewardsReceiver.address);
    await rewardsReceiver.work();
    afterBalance = await deployer.provider.getBalance(rewardsReceiver.address);
    expect(afterBalance).to.eq(prevBalance - (parseEther("1")));
  });

  it("flipState", async () => {
    await expect(rewardsReceiver.connect(alice).flipState()).to.be.revertedWith("Ownable: caller is not the owner");

    expect(await rewardsReceiver.state()).to.eq(0);
    await rewardsReceiver.flipState();
    expect(await rewardsReceiver.state()).to.eq(1);
  });
});
