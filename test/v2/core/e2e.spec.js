const {ethers} = require("hardhat");
const {expect} = require("chai");
const {parseEther} = require("ethers/lib/utils");

describe("e2e test", () => {
  let sgEth, deployer, alice, multiSig;
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

    // deploy sgeth
    const WSGETH = await ethers.getContractFactory("WSGETH");
    const wsgETH = await WSGETH.deploy(sgEth.address, 24 * 60 * 60);
    await wsgETH.deployed();

    const splitterAddresses = [deployer.address, multiSig.address, wsgETH.address];
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
      paymentSplitter.address, // fee splitter
      sgEth.address, // sgETH address
      wsgETH.address, // wsgETH address
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
      wsgETH.address,
      paymentSplitter.address,
      minter.address,
    ]);
    await rewardsReceiver.deployed();
  });

  it("e2e test", async () => {
    // deployer can't mint
    await expect(sgEth.connect(deployer).mint(deployer.address, parseEther("1"))).to.be.revertedWith(
      `AccessControl: account ${deployer.address.toLowerCase()} is missing role ${MINTER_ROLE}`,
    );
    // no one can't mint
    await expect(sgEth.connect(alice).mint(alice.address, parseEther("1"))).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${MINTER_ROLE}`,
    );
    // add minter
    await expect(sgEth.connect(deployer).addMinter(deployer.address))
      .to.be.emit(sgEth, "RoleGranted")
      .withArgs(MINTER_ROLE, deployer.address, deployer.address);
    // minter can mint
    await expect(sgEth.connect(deployer).mint(deployer.address, parseEther("1")))
      .to.be.emit(sgEth, "Transfer")
      .withArgs(ethers.constants.AddressZero, deployer.address, parseEther("1"));

    await sgEth.removeMinter(deployer.address);
    // add secondary owner
    // revoke deployer admin rights
    await expect(sgEth.transferOwnership(multiSig.address))
      .to.be.emit(sgEth, "RoleGranted")
      .withArgs(ethers.constants.HashZero, multiSig.address, deployer.address)
      .and.to.be.emit(sgEth, "RoleRevoked")
      .withArgs(ethers.constants.HashZero, deployer.address, deployer.address);

    // check auth invariants are preserved. i.e ex owner and outsiders cannot interact with the contract
    await expect(sgEth.connect(deployer).transferOwnership(alice.address)).to.be.revertedWith(
      `AccessControl: account ${deployer.address.toLowerCase()} is missing role ${ethers.constants.HashZero}`,
    );
  });
});
