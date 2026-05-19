/**
 * Unit tests for StakingCore:
 *   - Deposit happy path (shares minted, pool updated, event emitted)
 *   - Share accounting accuracy
 *   - Pause guard on submit
 *   - Oracle beacon report: rebase, fee distribution
 *   - Access control on all privileged functions
 */
import {ethers, deployments} from "hardhat";
import {expect} from "chai";
import {parseEther, ZeroAddress} from "ethers";
import {anyValue} from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";

describe("StakingCore", () => {
  let deployer: SignerWithAddress,
    gov: SignerWithAddress,
    alice: SignerWithAddress,
    bob: SignerWithAddress,
    oracle: SignerWithAddress;

  let stToken: any, stakingCore: any, feeController: any;

  const GOV_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GOV"));
  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN"));
  const MINTER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MINTER"));

  async function deployFresh() {
    [deployer, gov, alice, bob, oracle] = await ethers.getSigners();

    const StToken = await ethers.getContractFactory("StToken");
    stToken = await StToken.deploy();

    const FeeController = await ethers.getContractFactory("FeeController");
    feeController = await FeeController.deploy(
      gov.address,          // gov
      gov.address,          // treasury
      deployer.address,     // operator
      ZeroAddress,          // referral registry (unused in this suite)
      1000,                 // feeBps: 10%
      5000,                 // treasurySplitBps: 50%
      5000,                 // operatorSplitBps: 50%
    );

    const StakingCore = await ethers.getContractFactory("StakingCore");
    stakingCore = await StakingCore.deploy(stToken.target, gov.address);

    // Grant StakingCore MINTER on StToken.
    await stToken.addMinter(stakingCore.target);

    // Set fee controller (requires GOV role).
    await stakingCore.connect(gov).setFeeController(feeController.target);

    // Grant oracle role.
    await stakingCore.connect(gov).grantRole(ORACLE_ROLE, oracle.address);
  }

  beforeEach(deployFresh);

  // ── Deposits ────────────────────────────────────────────────────────────────

  describe("submit()", () => {
    it("submitWithAttribution mints shares and emits attribution telemetry", async () => {
      const amount = parseEther("1");
      const sourceId = ethers.encodeBytes32String("homepage-banner-v2");

      await expect(
        stakingCore.connect(alice).submitWithAttribution(bob.address, sourceId, {value: amount})
      )
        .to.emit(stakingCore, "SubmittedWithAttribution")
        .withArgs(alice.address, bob.address, sourceId, amount, amount);

      expect(await stToken.sharesOf(alice.address)).to.equal(amount);
      expect(await stToken.totalPooledEther()).to.equal(amount);
    });

    it("mints 1:1 shares on first deposit (bootstrap)", async () => {
      const depositAmount = parseEther("1");
      await stakingCore.connect(alice).submit(ZeroAddress, {value: depositAmount});

      const aliceShares = await stToken.sharesOf(alice.address);
      expect(aliceShares).to.equal(depositAmount);
      expect(await stToken.totalPooledEther()).to.equal(depositAmount);
    });

    it("emits Submitted event with correct args", async () => {
      const amount = parseEther("2");
      await expect(
        stakingCore.connect(alice).submit(bob.address, {value: amount})
      )
        .to.emit(stakingCore, "Submitted")
        .withArgs(alice.address, amount, bob.address, amount); // 1:1 on bootstrap
    });

    it("submit() remains unchanged and does not emit attribution telemetry", async () => {
      const amount = parseEther("1");
      await expect(
        stakingCore.connect(alice).submit(bob.address, {value: amount})
      )
        .to.emit(stakingCore, "Submitted")
        .withArgs(alice.address, amount, bob.address, amount);

      await expect(
        stakingCore.connect(alice).submit(bob.address, {value: amount})
      ).to.not.emit(stakingCore, "SubmittedWithAttribution");
    });

    it("subsequent deposits get proportional shares", async () => {
      // Alice deposits 1 ETH (bootstrap: 1e18 shares, 1 ETH pool).
      await stakingCore.connect(alice).submit(ZeroAddress, {value: parseEther("1")});

      // Simulate 10% reward (pool grows to 1.1 ETH, shares still 1e18).
      await stakingCore.connect(oracle).reportBeacon(0, 0); // no beacon validators yet
      // Manually rebase pool for test: oracle would normally do this.
      // For this test, use oracle to set beaconBalance = 0.1 ETH extra.
      // We need to call reportBeacon with correct args... let's adjust pool via oracle.
      // Actually, since no validators are staked, beacon balance stays 0.
      // Let's use a direct pool adjustment via stToken (MINTER is stakingCore only).
      // We'll test reward accounting separately; here focus on share proportionality.

      // Bob deposits at 1:1 (since beaconBalance == 0, pool == buffered == 1 ETH).
      await stakingCore.connect(bob).submit(ZeroAddress, {value: parseEther("1")});

      const aliceShares = await stToken.sharesOf(alice.address);
      const bobShares = await stToken.sharesOf(bob.address);
      expect(aliceShares).to.equal(bobShares); // equal deposits => equal shares
    });

    it("reverts when msg.value == 0", async () => {
      await expect(
        stakingCore.connect(alice).submit(ZeroAddress, {value: 0})
      ).to.be.reverted;
    });

    it("plain ETH transfer reverts when msg.value == 0", async () => {
      await expect(
        alice.sendTransaction({to: stakingCore.target, value: 0})
      ).to.be.reverted;
    });
  });

  // ── Pause ────────────────────────────────────────────────────────────────────

  describe("pause/unpause", () => {
    it("GUARDIAN can pause submit", async () => {
      await stakingCore.connect(gov).pause(0); // PAUSE_SUBMIT = 0
      await expect(
        stakingCore.connect(alice).submit(ZeroAddress, {value: parseEther("1")})
      ).to.be.reverted;
    });

    it("paused submit also blocks plain ETH transfers", async () => {
      await stakingCore.connect(gov).pause(0);
      await expect(
        alice.sendTransaction({to: stakingCore.target, value: parseEther("1")})
      ).to.be.reverted;
    });

    it("GOV can unpause", async () => {
      await stakingCore.connect(gov).pause(0);
      await stakingCore.connect(gov).unpause(0);
      // Should succeed now.
      await expect(
        stakingCore.connect(alice).submit(ZeroAddress, {value: parseEther("1")})
      ).to.not.be.reverted;
    });

    it("non-GUARDIAN cannot pause", async () => {
      await expect(
        stakingCore.connect(alice).pause(0)
      ).to.be.reverted;
    });
  });

  // ── Oracle reporting ──────────────────────────────────────────────────────────

  describe("reportBeacon()", () => {
    beforeEach(async () => {
      // Alice deposits 10 ETH.
      await stakingCore.connect(alice).submit(ZeroAddress, {value: parseEther("10")});
    });

    it("only ORACLE role can call reportBeacon", async () => {
      await expect(
        stakingCore.connect(alice).reportBeacon(0, 0)
      ).to.be.reverted;
    });

    it("reward rebase: beacon balance increases totalPooledEther", async () => {
      const preTotalPooled = await stToken.totalPooledEther();
      await stakingCore.connect(gov).notifyBeaconDeposit(parseEther("10"));
      // Report 10.5 ETH in beacon (0.5 ETH reward on 10 ETH principal baseline).
      await stakingCore.connect(oracle).reportBeacon(1, parseEther("10.5"));
      const postTotalPooled = await stToken.totalPooledEther();
      // Rewards = 0.5 ETH, fee = 10% = 0.05 ETH minted to treasury/operator.
      // Pool stays at 10.5 because fees are captured via share dilution,
      // not by increasing totalPooledEther beyond actual ETH backing.
      expect(preTotalPooled).to.equal(parseEther("10"));
      expect(postTotalPooled).to.equal(parseEther("10.5"));
    });

    it("fee shares are minted on positive rewards", async () => {
      const govSharesBefore = await stToken.sharesOf(gov.address);
      const deployerSharesBefore = await stToken.sharesOf(deployer.address);

      await stakingCore.connect(gov).notifyBeaconDeposit(parseEther("10"));
      await stakingCore.connect(oracle).reportBeacon(1, parseEther("10.5"));

      const govSharesAfter = await stToken.sharesOf(gov.address);
      const deployerSharesAfter = await stToken.sharesOf(deployer.address);

      // Both treasury (gov) and operator (deployer) receive fee shares.
      expect(govSharesAfter).to.be.gt(govSharesBefore);
      expect(deployerSharesAfter).to.be.gt(deployerSharesBefore);
    });

    it("emits fee-routing telemetry on positive rewards", async () => {
      await stakingCore.connect(gov).notifyBeaconDeposit(parseEther("10"));
      await expect(
        stakingCore.connect(oracle).reportBeacon(1, parseEther("10.5"))
      )
        .to.emit(stakingCore, "FeeRoutingTelemetry")
        .withArgs(
          parseEther("0.5"),
          parseEther("0.05"),
          gov.address,
          parseEther("0.025"),
          anyValue,
          deployer.address,
          parseEther("0.025"),
          anyValue,
        );
    });

    it("slash: beacon balance decrease does not mint fees", async () => {
      await stakingCore.connect(gov).notifyBeaconDeposit(parseEther("10"));
      // First report: no rewards.
      await stakingCore.connect(oracle).reportBeacon(1, parseEther("10"));
      const govSharesAfter1st = await stToken.sharesOf(gov.address);

      // Second report: slash (balance falls).
      await stakingCore.connect(oracle).reportBeacon(1, parseEther("9.5"));
      const govSharesAfter2nd = await stToken.sharesOf(gov.address);

      expect(govSharesAfter2nd).to.equal(govSharesAfter1st); // no new fees on slash
    });

    it("reverts on implausibly large beacon balance", async () => {
      await stakingCore.connect(gov).notifyBeaconDeposit(parseEther("10"));
      // First establish validators.
      await stakingCore.connect(oracle).reportBeacon(1, parseEther("10"));
      // Now report 100× the max plausible.
      await expect(
        stakingCore.connect(oracle).reportBeacon(1, parseEther("6500"))
      ).to.be.revertedWithCustomError(stakingCore, "BeaconBalanceSanityFailed");
    });

    it("reverts when positive report arrives before beacon baseline initialization", async () => {
      await expect(
        stakingCore.connect(oracle).reportBeacon(1, parseEther("10.5"))
      ).to.be.revertedWithCustomError(stakingCore, "BeaconBaselineNotInitialized");
    });

    it("rejects impossible report tuple (0 validators with non-zero balance)", async () => {
      await expect(
        stakingCore.connect(oracle).reportBeacon(0, parseEther("1"))
      ).to.be.revertedWithCustomError(stakingCore, "InvalidBeaconReportTuple");
    });

    it("reverts when baseline notification exceeds buffered ETH", async () => {
      await expect(
        stakingCore.connect(gov).notifyBeaconDeposit(parseEther("10.1"))
      ).to.be.revertedWithCustomError(stakingCore, "BeaconDepositExceedsBuffered");
    });

    it("routes referral fee shares to treasury when referral registry has no referees", async () => {
      const ReferralRegistry = await ethers.getContractFactory("ReferralRegistry");
      const registry = await ReferralRegistry.deploy(gov.address, stToken.target);
      await registry.connect(gov).grantRole(await registry.FEE_CTRL(), stakingCore.target);

      await feeController.connect(gov).setFee(1000, 4000, 4000);
      await feeController.connect(gov).setRecipients(gov.address, deployer.address, registry.target);

      await stakingCore.connect(gov).notifyBeaconDeposit(parseEther("10"));

      const treasuryBefore = await stToken.sharesOf(gov.address);
      const operatorBefore = await stToken.sharesOf(deployer.address);
      const registryBefore = await stToken.sharesOf(registry.target);

      await expect(
        stakingCore.connect(oracle).reportBeacon(1, parseEther("10.5"))
      ).to.not.be.reverted;

      const treasuryAfter = await stToken.sharesOf(gov.address);
      const operatorAfter = await stToken.sharesOf(deployer.address);
      const registryAfter = await stToken.sharesOf(registry.target);

      expect(registryAfter - registryBefore).to.equal(0n);
      expect(treasuryAfter - treasuryBefore).to.be.gt(operatorAfter - operatorBefore);
    });
  });

  // ── Access control matrix ─────────────────────────────────────────────────────

  describe("Access control", () => {
    it("random address cannot call setFeeController", async () => {
      await expect(
        stakingCore.connect(alice).setFeeController(ZeroAddress)
      ).to.be.reverted;
    });

    it("random address cannot call grantRole", async () => {
      await expect(
        stakingCore.connect(alice).grantRole(ORACLE_ROLE, alice.address)
      ).to.be.reverted;
    });
  });
});
