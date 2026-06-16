import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";
import {
  SharedDepositMinterV2,
  SharedDepositMinterV2__factory,
  WSGETH,
  WSGETH__factory,
  WithdrawalQueue,
  SgETH,
  SgETH__factory,
} from "../../../types";
import chai from "chai";
import {deployments, ethers as hreEthers} from "hardhat";
import Ship from "../../../utils/ship";
import {parseEther} from "ethers";
import {advanceTimeAndBlock} from "../../../utils/time";

const {expect} = chai;

// Mainnet addresses for forking
const MAINNET_VETH2 = "0x898bad2774eb97cf6b94605677f43b41871410b1"; // vETH2 on mainnet
const FORK_BLOCK_NUMBER = 19500000; // Recent mainnet block for consistent testing

describe("WithdrawalQueue E2E - Mainnet Fork", () => {
  let ship: Ship;
  let withdrawalQueueERC4626: WithdrawalQueue;
  let withdrawalQueueFixed: WithdrawalQueue;
  let minter: SharedDepositMinterV2;
  let wsgEth: WSGETH;
  let sgEth: SgETH;
  let deployer: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;
  let vEth2: any; // vETH2 contract on mainnet

  const EPOCH_LENGTH = 100; // 100 blocks for realistic testing

  before(async function () {
    // Skip if no ALCHEMY_KEY or MAINNET_RPC_URL configured
    if (!process.env.ALCHEMY_KEY) {
      this.skip();
      return;
    }

    // Fork mainnet using Anvil
    await hreEthers.provider.send("hardhat_reset", [
      {
        forking: {
          jsonRpcUrl: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
          blockNumber: FORK_BLOCK_NUMBER,
        },
      },
    ]);

    ship = await Ship.init();
    const {accounts} = ship;
    deployer = accounts.deployer;
    alice = accounts.alice;
    bob = accounts.bob;

    // Impersonate a whale account with ETH for testing
    const whaleAddress = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"; // Vitalik's address (has ETH)
    await hreEthers.provider.send("hardhat_impersonateAccount", [whaleAddress]);
    const whale = await hreEthers.getSigner(whaleAddress);
    await deployer.sendTransaction({
      to: whaleAddress,
      value: parseEther("100"),
    });

    // Get vETH2 contract from mainnet
    const vEth2Abi = [
      "function balanceOf(address) view returns (uint256)",
      "function transfer(address, uint256) returns (bool)",
      "function approve(address, uint256) returns (bool)",
    ];
    vEth2 = await hreEthers.getContractAt(vEth2Abi, MAINNET_VETH2);

    // Try to get vETH2 tokens from whale if available
    const whaleVeth2Balance = await vEth2.balanceOf(whaleAddress);
    if (whaleVeth2Balance > parseEther("100")) {
      await vEth2.connect(whale).transfer(alice.address, parseEther("50"));
      await vEth2.connect(whale).transfer(bob.address, parseEther("50"));
      await vEth2.connect(whale).transfer(deployer.address, parseEther("100"));
    }

    // Deploy our contracts on the fork
    await deployments.fixture(["sgEth", "minter", "wsgEth"]);

    sgEth = await ship.connect(SgETH__factory);
    minter = await ship.connect(SharedDepositMinterV2__factory);
    wsgEth = await ship.connect(WSGETH__factory);

    // Setup: Get some WSGETH tokens for testing
    await sgEth.connect(deployer).addMinter(deployer.address);
    await sgEth.connect(deployer).mint(deployer.address, parseEther("1000"));
    await sgEth.connect(deployer).mint(alice.address, parseEther("100"));
    await sgEth.connect(deployer).mint(bob.address, parseEther("100"));

    // Stake SGETH to get WSGETH
    await sgEth.connect(deployer).approve(wsgEth.target, parseEther("1000"));
    await sgEth.connect(alice).approve(wsgEth.target, parseEther("100"));
    await sgEth.connect(bob).approve(wsgEth.target, parseEther("100"));

    await wsgEth.connect(deployer).deposit(parseEther("500"), deployer.address);
    await wsgEth.connect(alice).deposit(parseEther("50"), alice.address);
    await wsgEth.connect(bob).deposit(parseEther("50"), bob.address);

    // Deploy WithdrawalQueue in ERC4626 mode
    const WithdrawalQueueFactory = await hreEthers.getContractFactory("WithdrawalQueue");
    withdrawalQueueERC4626 = await WithdrawalQueueFactory.deploy(
      minter.target,
      wsgEth.target,
      EPOCH_LENGTH,
      0, // ERC4626 mode
    );

    // Deploy WithdrawalQueue in Fixed Price mode (for vETH2)
    // Use 1:1 virtual price (1e18) for vETH2
    const VIRTUAL_PRICE_FIXED = parseEther("1"); // 1:1 exchange rate
    withdrawalQueueFixed = await WithdrawalQueueFactory.deploy(
      hreEthers.ZeroAddress, // No minter for fixed price mode
      MAINNET_VETH2,
      EPOCH_LENGTH,
      VIRTUAL_PRICE_FIXED,
    );

    // Fund withdrawal queues with ETH for redemptions
    await deployer.sendTransaction({
      to: withdrawalQueueERC4626.target,
      value: parseEther("50"),
    });
    await deployer.sendTransaction({
      to: withdrawalQueueFixed.target,
      value: parseEther("50"),
    });

    // Fund minter with ETH
    await deployer.sendTransaction({
      to: minter.target,
      value: parseEther("100"),
    });

    // Approve withdrawal queues
    await wsgEth.connect(deployer).approve(withdrawalQueueERC4626.target, parseEther("500"));
    await wsgEth.connect(alice).approve(withdrawalQueueERC4626.target, parseEther("50"));
    await wsgEth.connect(bob).approve(withdrawalQueueERC4626.target, parseEther("50"));

    // Approve fixed price withdrawal queue for vETH2 (if tokens available)
    const aliceVeth2Balance = await vEth2.balanceOf(alice.address);
    if (aliceVeth2Balance > 0n) {
      await vEth2.connect(alice).approve(withdrawalQueueFixed.target, parseEther("1000"));
      await vEth2.connect(bob).approve(withdrawalQueueFixed.target, parseEther("1000"));
      await vEth2.connect(deployer).approve(withdrawalQueueFixed.target, parseEther("1000"));
    }
  });

  describe("ERC4626 Mode (WSGETH) - E2E", () => {
    it("should complete full redemption flow with real WSGETH", async function () {
      if (!process.env.ALCHEMY_KEY) {
        this.skip();
        return;
      }

      const shares = parseEther("10");
      const aliceBalanceBefore = await hreEthers.provider.getBalance(alice.address);
      const wsgEthBalanceBefore = await wsgEth.balanceOf(alice.address);

      // Request redemption
      await expect(withdrawalQueueERC4626.connect(alice).requestRedeem(shares)).to.emit(
        withdrawalQueueERC4626,
        "RedeemRequest",
      );

      expect(await withdrawalQueueERC4626.pendingRedeemRequest(alice.address)).to.be.gt(0);

      // Wait for epoch
      await advanceTimeAndBlock(EPOCH_LENGTH);

      // Redeem
      const assets = await wsgEth.previewRedeem(shares);
      await expect(withdrawalQueueERC4626.connect(alice).redeem(shares, alice.address)).to.emit(
        withdrawalQueueERC4626,
        "Redeem",
      );

      const aliceBalanceAfter = await hreEthers.provider.getBalance(alice.address);
      const wsgEthBalanceAfter = await wsgEth.balanceOf(alice.address);

      // Verify WSGETH was burned
      expect(wsgEthBalanceAfter).to.be.lt(wsgEthBalanceBefore);
      // Verify ETH was received (approximate due to gas)
      expect(aliceBalanceAfter - aliceBalanceBefore).to.be.closeTo(assets, parseEther("0.1"));
    });

    it("should handle multiple users in FIFO queue", async function () {
      if (!process.env.ALCHEMY_KEY) {
        this.skip();
        return;
      }

      // Alice requests first
      await withdrawalQueueERC4626.connect(alice).requestRedeem(parseEther("5"));
      // Bob requests second
      await withdrawalQueueERC4626.connect(bob).requestRedeem(parseEther("5"));

      expect(await withdrawalQueueERC4626.pendingRedeemRequest(alice.address)).to.be.gt(0);
      expect(await withdrawalQueueERC4626.pendingRedeemRequest(bob.address)).to.be.gt(0);

      await advanceTimeAndBlock(EPOCH_LENGTH);

      // Both should be claimable
      expect(await withdrawalQueueERC4626.claimableRedeemRequest(alice.address)).to.be.gt(0);
      expect(await withdrawalQueueERC4626.claimableRedeemRequest(bob.address)).to.be.gt(0);

      // Alice redeems first
      await withdrawalQueueERC4626.connect(alice).redeem(parseEther("5"), alice.address);
      // Bob redeems second
      await withdrawalQueueERC4626.connect(bob).redeem(parseEther("5"), bob.address);

      expect(await withdrawalQueueERC4626.pendingRedeemRequest(alice.address)).to.eq(0);
      expect(await withdrawalQueueERC4626.pendingRedeemRequest(bob.address)).to.eq(0);
    });

    it("should cancel redemption and return WSGETH", async function () {
      if (!process.env.ALCHEMY_KEY) {
        this.skip();
        return;
      }

      const shares = parseEther("5");
      const wsgEthBalanceBefore = await wsgEth.balanceOf(alice.address);

      await withdrawalQueueERC4626.connect(alice).requestRedeem(shares);
      await advanceTimeAndBlock(EPOCH_LENGTH);

      await withdrawalQueueERC4626.connect(alice).cancelRedeem(alice.address);

      const wsgEthBalanceAfter = await wsgEth.balanceOf(alice.address);
      expect(wsgEthBalanceAfter - wsgEthBalanceBefore).to.eq(shares);
      expect(await withdrawalQueueERC4626.pendingRedeemRequest(alice.address)).to.eq(0);
    });
  });

  describe("Fixed Price Mode (vETH2) - E2E", () => {
    it("should complete full redemption flow with real vETH2", async function () {
      if (!process.env.ALCHEMY_KEY) {
        this.skip();
        return;
      }

      // Check if we have vETH2 tokens
      const aliceVeth2Balance = await vEth2.balanceOf(alice.address);
      if (aliceVeth2Balance === 0n) {
        this.skip(); // Skip if no vETH2 tokens available
        return;
      }

      const shares = aliceVeth2Balance > parseEther("10") ? parseEther("10") : aliceVeth2Balance / 2n;
      const aliceBalanceBefore = await hreEthers.provider.getBalance(alice.address);

      // Request redemption
      await expect(withdrawalQueueFixed.connect(alice).requestRedeem(shares)).to.emit(
        withdrawalQueueFixed,
        "RedeemRequest",
      );

      expect(await withdrawalQueueFixed.pendingRedeemRequest(alice.address)).to.be.gt(0);

      // Wait for epoch
      await advanceTimeAndBlock(EPOCH_LENGTH);

      // Redeem
      // With fixed price 1:1, assets should equal shares
      const expectedAssets = shares; // 1:1 conversion with VIRTUAL_PRICE_FIXED = 1e18
      await expect(withdrawalQueueFixed.connect(alice).redeem(shares, alice.address)).to.emit(
        withdrawalQueueFixed,
        "Redeem",
      );

      const aliceBalanceAfter = await hreEthers.provider.getBalance(alice.address);

      // Verify ETH was received (approximate due to gas)
      expect(aliceBalanceAfter - aliceBalanceBefore).to.be.closeTo(expectedAssets, parseEther("0.1"));
    });

    it("should handle fixed price conversion correctly", async function () {
      if (!process.env.ALCHEMY_KEY) {
        this.skip();
        return;
      }

      const aliceVeth2Balance = await vEth2.balanceOf(alice.address);
      if (aliceVeth2Balance === 0n) {
        this.skip();
        return;
      }

      const shares = aliceVeth2Balance > parseEther("5") ? parseEther("5") : aliceVeth2Balance / 2n;
      const VIRTUAL_PRICE_FIXED = parseEther("1"); // 1:1 conversion

      await withdrawalQueueFixed.connect(alice).requestRedeem(shares);

      const pendingAssets = await withdrawalQueueFixed.pendingRedeemRequest(alice.address);
      const expectedAssets = (shares * VIRTUAL_PRICE_FIXED) / parseEther("1"); // Should be 1:1

      // Check that assets match expected conversion
      expect(pendingAssets).to.eq(expectedAssets);
    });
  });

  describe("Cross-Mode Scenarios", () => {
    it("should handle concurrent requests in both modes", async function () {
      if (!process.env.ALCHEMY_KEY) {
        this.skip();
        return;
      }

      // Request in ERC4626 mode
      await withdrawalQueueERC4626.connect(alice).requestRedeem(parseEther("3"));

      // Request in Fixed Price mode (if tokens available)
      const aliceVeth2Balance = await vEth2.balanceOf(alice.address);
      if (aliceVeth2Balance > parseEther("3")) {
        await withdrawalQueueFixed.connect(bob).requestRedeem(parseEther("3"));
      }

      await advanceTimeAndBlock(EPOCH_LENGTH);

      // Both should be claimable independently
      expect(await withdrawalQueueERC4626.claimableRedeemRequest(alice.address)).to.be.gt(0);
      if (aliceVeth2Balance > parseEther("3")) {
        expect(await withdrawalQueueFixed.claimableRedeemRequest(bob.address)).to.be.gt(0);
      }
    });

    it("should track totalAssetsOut correctly across modes", async function () {
      if (!process.env.ALCHEMY_KEY) {
        this.skip();
        return;
      }

      const initialERC4626Out = await withdrawalQueueERC4626.totalAssetsOut();
      const initialFixedOut = await withdrawalQueueFixed.totalAssetsOut();

      // Redeem in ERC4626 mode
      await withdrawalQueueERC4626.connect(alice).requestRedeem(parseEther("2"));
      await advanceTimeAndBlock(EPOCH_LENGTH);
      await withdrawalQueueERC4626.connect(alice).redeem(parseEther("2"), alice.address);

      const afterERC4626Out = await withdrawalQueueERC4626.totalAssetsOut();
      expect(afterERC4626Out).to.be.gt(initialERC4626Out);

      // Verify fixed price mode tracking is independent
      expect(await withdrawalQueueFixed.totalAssetsOut()).to.eq(initialFixedOut);
    });
  });
});
