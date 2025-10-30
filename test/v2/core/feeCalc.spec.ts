import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";
import {
  FeeCalc,
  FeeCalc__factory,
  SharedDepositMinterV2,
  SharedDepositMinterV2__factory,
  SgETH,
  SgETH__factory,
  WSGETH,
  WSGETH__factory,
} from "../../../types";
import chai from "chai";
import {deployments} from "hardhat";
import Ship from "../../../utils/ship";
import {parseEther} from "ethers";

const {expect} = chai;

let ship: Ship;
let feeCalc: FeeCalc,
  minter: SharedDepositMinterV2,
  sgEth: SgETH,
  deployer: SignerWithAddress,
  alice: SignerWithAddress;

const setup = deployments.createFixture(async hre => {
  ship = await Ship.init(hre);
  const {accounts} = ship;
  await deployments.fixture(["sgEth", "minter"]);

  return {
    ship,
    accounts,
  };
});

describe("FeeCalc - Critical Bug Fixes", () => {
  beforeEach(async () => {
    const {ship, accounts} = await setup();

    sgEth = await ship.connect(SgETH__factory);
    minter = await ship.connect(SharedDepositMinterV2__factory);
    deployer = accounts.deployer;
    alice = accounts.alice;

    // Deploy FeeCalc with chargeOnDeposit = false (the bug scenario)
    const FeeCalcFactory = await ship.hre.ethers.getContractFactory("FeeCalc");
    feeCalc = await FeeCalcFactory.deploy({
      adminFee: 100, // 1%
      exitFee: 50, // 0.5%
      refundFeesOnWithdraw: false,
      chargeOnDeposit: false, // CRITICAL: This was the bug scenario
      chargeOnExit: false,
    });

    // Set feeCalc in minter
    await minter.connect(accounts.multiSig).setFeeCalc(feeCalc.target);
  });

  describe("processDeposit - Critical Bug Fix", () => {
    it("should return correct values when chargeOnDeposit is false (BUG FIX)", async () => {
      // This test verifies the critical bug fix
      // Before fix: would return (amt=0, fee=0) causing users to lose funds
      // After fix: returns (amt=value, fee=0) correctly

      const depositAmount = parseEther("10");
      const result = await feeCalc.processDeposit(depositAmount, alice.address);

      expect(result.amt).to.eq(depositAmount);
      expect(result.fee).to.eq(0);
    });

    it("should work correctly when chargeOnDeposit is true", async () => {
      // Enable deposit fees
      await feeCalc.set({
        adminFee: 100, // 1%
        exitFee: 50,
        refundFeesOnWithdraw: false,
        chargeOnDeposit: true,
        chargeOnExit: false,
      });

      const depositAmount = parseEther("10");
      const result = await feeCalc.processDeposit(depositAmount, alice.address);

      const expectedFee = (depositAmount * BigInt(100)) / BigInt(10000); // 1%
      const expectedAmt = depositAmount - expectedFee;

      expect(result.amt).to.eq(expectedAmt);
      expect(result.fee).to.eq(expectedFee);
    });

    it("should allow deposits when chargeOnDeposit is false (integration test)", async () => {
      // Integration test: deposit through minter when chargeOnDeposit is false
      const depositAmount = parseEther("5");

      const prevBalance = await sgEth.balanceOf(alice.address);
      await minter.connect(alice).deposit({
        value: depositAmount,
      });
      const afterBalance = await sgEth.balanceOf(alice.address);

      // User should receive tokens equal to deposit (no fee when chargeOnDeposit is false)
      expect(afterBalance - prevBalance).to.eq(depositAmount);
    });
  });

  describe("processWithdraw", () => {
    it("should handle refundFeesOnWithdraw correctly", async () => {
      await feeCalc.set({
        adminFee: 100, // 1%
        exitFee: 50,
        refundFeesOnWithdraw: true,
        chargeOnDeposit: false,
        chargeOnExit: false,
      });

      const withdrawAmount = parseEther("10");
      const result = await feeCalc.processWithdraw(withdrawAmount, alice.address);

      const expectedFee = (withdrawAmount * BigInt(100)) / BigInt(10000);
      const expectedAmt = withdrawAmount + expectedFee; // Refund adds to amount

      expect(result.amt).to.eq(expectedAmt);
      expect(result.fee).to.eq(expectedFee);
    });

    it("should handle chargeOnExit correctly", async () => {
      await feeCalc.set({
        adminFee: 100,
        exitFee: 50, // 0.5%
        refundFeesOnWithdraw: false,
        chargeOnDeposit: false,
        chargeOnExit: true,
      });

      const withdrawAmount = parseEther("10");
      const result = await feeCalc.processWithdraw(withdrawAmount, alice.address);

      const expectedFee = (withdrawAmount * BigInt(50)) / BigInt(10000);
      const expectedAmt = withdrawAmount - expectedFee;

      expect(result.amt).to.eq(expectedAmt);
      expect(result.fee).to.eq(expectedFee);
    });

    it("should return original amount when no fees apply", async () => {
      await feeCalc.set({
        adminFee: 100,
        exitFee: 50,
        refundFeesOnWithdraw: false,
        chargeOnDeposit: false,
        chargeOnExit: false,
      });

      const withdrawAmount = parseEther("10");
      const result = await feeCalc.processWithdraw(withdrawAmount, alice.address);

      expect(result.amt).to.eq(withdrawAmount);
      expect(result.fee).to.eq(0);
    });
  });

  describe("Validation", () => {
    it("should revert when adminFee exceeds 100%", async () => {
      await expect(
        feeCalc.set({
          adminFee: 10001, // > 100%
          exitFee: 50,
          refundFeesOnWithdraw: false,
          chargeOnDeposit: false,
          chargeOnExit: false,
        }),
      ).to.be.revertedWithCustomError(feeCalc, "FeeTooHigh");
    });

    it("should revert when exitFee exceeds 100%", async () => {
      await expect(
        feeCalc.set({
          adminFee: 100,
          exitFee: 10001, // > 100%
          refundFeesOnWithdraw: false,
          chargeOnDeposit: false,
          chargeOnExit: false,
        }),
      ).to.be.revertedWithCustomError(feeCalc, "FeeTooHigh");
    });

    it("should allow setting fees to exactly 100%", async () => {
      await expect(
        feeCalc.set({
          adminFee: 10000, // Exactly 100%
          exitFee: 10000,
          refundFeesOnWithdraw: false,
          chargeOnDeposit: false,
          chargeOnExit: false,
        }),
      ).to.not.be.reverted;
    });
  });
});
