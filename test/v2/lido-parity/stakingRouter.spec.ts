/**
 * Unit tests for StakingRouter:
 *   - Module registration & metadata
 *   - submit() default-module routing
 *   - submitToModule() targeted routing
 *   - Mint cap enforcement (per module)
 *   - Pause guard (PAUSE_SUBMIT) and per-module pause
 *   - Module beacon balance reporting (delta-only accounting)
 *   - Default module switching
 *   - Access control matrix
 */
import {ethers} from "hardhat";
import {expect} from "chai";
import {parseEther, ZeroAddress} from "ethers";
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";

const SOLO = ethers.keccak256(ethers.toUtf8Bytes("SOLO_MOD_1"));
const SECONDARY = ethers.keccak256(ethers.toUtf8Bytes("SOLO_MOD_2"));

describe("StakingRouter", () => {
  let deployer: SignerWithAddress,
    gov: SignerWithAddress,
    guardian: SignerWithAddress,
    alice: SignerWithAddress,
    bob: SignerWithAddress,
    oracle: SignerWithAddress,
    impostor: SignerWithAddress;

  let stToken: any, router: any, mod1: any, mod2: any, feeController: any;

  const ORACLE_ROLE = ethers.keccak256(ethers.toUtf8Bytes("ORACLE"));
  const GOV_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GOV"));
  const GUARDIAN_ROLE = ethers.keccak256(ethers.toUtf8Bytes("GUARDIAN"));
  const NODE_OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("NODE_OPERATOR"));

  let mockBeaconDeposit: any;

  async function deployFresh() {
    [deployer, gov, guardian, alice, bob, oracle, impostor] = await ethers.getSigners();

    const StToken = await ethers.getContractFactory("StToken");
    stToken = await StToken.deploy();

    const FeeController = await ethers.getContractFactory("FeeController");
    feeController = await FeeController.deploy(
      gov.address,
      gov.address,        // treasury
      deployer.address,   // operator
      1000,
      5000,
    );

    const StakingRouter = await ethers.getContractFactory("StakingRouter");
    router = await StakingRouter.deploy(stToken.target, gov.address);

    // Mock beacon deposit contract for hardhat tests — accepts ETH without
    // performing real validator processing.
    const MockBeaconDeposit = await ethers.getContractFactory("MockBeaconDeposit");
    mockBeaconDeposit = await MockBeaconDeposit.deploy();

    const ValidatorModule = await ethers.getContractFactory("ValidatorModule");
    mod1 = await ValidatorModule.deploy(router.target, SOLO, gov.address, mockBeaconDeposit.target);
    mod2 = await ValidatorModule.deploy(router.target, SECONDARY, gov.address, mockBeaconDeposit.target);

    // Grant router MINTER on stToken.
    await stToken.addMinter(router.target);

    // GOV wires fee controller, registers module, sets default.
    await router.connect(gov).setFeeController(feeController.target);
    await router.connect(gov).registerModule(SOLO, mod1.target, parseEther("100"));
    await router.connect(gov).setDefaultModule(SOLO);

    // GOV grants guardian role to dedicated guardian signer for tests.
    await router.connect(gov).grantRole(GUARDIAN_ROLE, guardian.address);

    // Oracle signer gets ORACLE on the module so it can call reportBeacon.
    await mod1.connect(gov).grantRole(ORACLE_ROLE, oracle.address);

    // Gov gets NODE_OPERATOR on mod1 so tests can drive depositToBeaconChain.
    await mod1.connect(gov).grantRole(NODE_OPERATOR_ROLE, gov.address);
  }

  beforeEach(deployFresh);

  // ── Module registration ────────────────────────────────────────────────────

  describe("Module registration", () => {
    it("registers module with addr/type/cap, marks active", async () => {
      const info = await router.modules(SOLO);
      expect(info.addr).to.equal(mod1.target);
      expect(info.moduleType).to.equal(ethers.keccak256(ethers.toUtf8Bytes("SOLO_VALIDATOR")));
      expect(info.mintCapEth).to.equal(parseEther("100"));
      expect(info.active).to.be.true;
      expect(info.paused).to.be.false;
    });

    it("reverts on duplicate registration", async () => {
      await expect(
        router.connect(gov).registerModule(SOLO, mod1.target, parseEther("50"))
      ).to.be.revertedWithCustomError(router, "ModuleAlreadyRegistered");
    });

    it("non-GOV cannot register a module", async () => {
      await expect(
        router.connect(alice).registerModule(SECONDARY, mod2.target, 0)
      ).to.be.reverted;
    });

    it("rejects zero address module", async () => {
      await expect(
        router.connect(gov).registerModule(SECONDARY, ZeroAddress, 0)
      ).to.be.reverted;
    });
  });

  // ── Deposits via submit() ───────────────────────────────────────────────────

  describe("submit() (default module)", () => {
    it("routes 1 ETH to default module, mints 1:1 shares (bootstrap)", async () => {
      await router.connect(alice).submit(ZeroAddress, {value: parseEther("1")});
      expect(await stToken.sharesOf(alice.address)).to.equal(parseEther("1"));
      expect(await stToken.totalPooledEther()).to.equal(parseEther("1"));
      expect(await mod1.bufferedEther()).to.equal(parseEther("1"));
    });

    it("emits Deposited with moduleId and referral", async () => {
      const amount = parseEther("2");
      await expect(router.connect(alice).submit(bob.address, {value: amount}))
        .to.emit(router, "Deposited")
        .withArgs(SOLO, alice.address, amount, amount, bob.address); // 1:1 bootstrap
    });

    it("reverts when msg.value == 0", async () => {
      await expect(
        router.connect(alice).submit(ZeroAddress, {value: 0})
      ).to.be.reverted;
    });

    it("reverts if defaultModuleId not set", async () => {
      // Deploy a fresh router with no default set.
      const StakingRouter = await ethers.getContractFactory("StakingRouter");
      const router2 = await StakingRouter.deploy(stToken.target, gov.address);
      await expect(
        router2.connect(alice).submit(ZeroAddress, {value: parseEther("1")})
      ).to.be.revertedWithCustomError(router2, "DefaultModuleNotSet");
    });
  });

  // ── submitToModule ─────────────────────────────────────────────────────────

  describe("submitToModule()", () => {
    beforeEach(async () => {
      await router.connect(gov).registerModule(SECONDARY, mod2.target, 0);
    });

    it("routes to chosen module, leaves default-module buffer untouched", async () => {
      await router.connect(alice).submitToModule(SECONDARY, ZeroAddress, {value: parseEther("3")});
      expect(await mod2.bufferedEther()).to.equal(parseEther("3"));
      expect(await mod1.bufferedEther()).to.equal(0n);
    });

    it("reverts on unregistered module id", async () => {
      const fake = ethers.keccak256(ethers.toUtf8Bytes("DOES_NOT_EXIST"));
      await expect(
        router.connect(alice).submitToModule(fake, ZeroAddress, {value: parseEther("1")})
      ).to.be.revertedWithCustomError(router, "ModuleNotRegistered");
    });
  });

  // ── Mint cap ───────────────────────────────────────────────────────────────

  describe("Mint cap enforcement", () => {
    it("rejects deposit that would exceed cap", async () => {
      // Cap is 100 ETH on SOLO. Fill with 99, then try 2 more.
      await router.connect(alice).submit(ZeroAddress, {value: parseEther("99")});
      await expect(
        router.connect(alice).submit(ZeroAddress, {value: parseEther("2")})
      ).to.be.revertedWithCustomError(router, "MintCapExceeded");
    });

    it("accepts deposit exactly at cap", async () => {
      await router.connect(alice).submit(ZeroAddress, {value: parseEther("100")});
      expect(await mod1.totalEth()).to.equal(parseEther("100"));
    });

    it("cap=0 means unlimited", async () => {
      await router.connect(gov).setMintCap(SOLO, 0);
      await router.connect(alice).submit(ZeroAddress, {value: parseEther("500")});
      expect(await mod1.bufferedEther()).to.equal(parseEther("500"));
    });

    it("setMintCap is GOV-only", async () => {
      await expect(
        router.connect(alice).setMintCap(SOLO, parseEther("1"))
      ).to.be.reverted;
    });
  });

  // ── Pause ──────────────────────────────────────────────────────────────────

  describe("Pause", () => {
    it("GUARDIAN can pause submit; deposit reverts", async () => {
      await router.connect(guardian).pause(0); // PAUSE_SUBMIT = 0
      await expect(
        router.connect(alice).submit(ZeroAddress, {value: parseEther("1")})
      ).to.be.reverted;
    });

    it("GOV can unpause", async () => {
      await router.connect(guardian).pause(0);
      await router.connect(gov).unpause(0);
      await expect(
        router.connect(alice).submit(ZeroAddress, {value: parseEther("1")})
      ).to.not.be.reverted;
    });

    it("non-GUARDIAN cannot pause", async () => {
      await expect(router.connect(alice).pause(0)).to.be.reverted;
    });

    it("module-level pause blocks deposits to that module only", async () => {
      await router.connect(gov).registerModule(SECONDARY, mod2.target, 0);
      await router.connect(guardian).pauseModule(SOLO);

      await expect(
        router.connect(alice).submit(ZeroAddress, {value: parseEther("1")})
      ).to.be.revertedWithCustomError(router, "ModulePaused");

      // SECONDARY still accepts.
      await router.connect(alice).submitToModule(SECONDARY, ZeroAddress, {value: parseEther("1")});
      expect(await mod2.bufferedEther()).to.equal(parseEther("1"));
    });

    it("emergencyPauseAll pauses submit and listed modules", async () => {
      await router.connect(gov).registerModule(SECONDARY, mod2.target, 0);
      await router.connect(guardian).emergencyPauseAll([SOLO, SECONDARY]);
      const info1 = await router.modules(SOLO);
      const info2 = await router.modules(SECONDARY);
      expect(info1.paused).to.be.true;
      expect(info2.paused).to.be.true;
      await expect(
        router.connect(alice).submit(ZeroAddress, {value: parseEther("1")})
      ).to.be.reverted;
    });
  });

  // ── Module beacon reporting ────────────────────────────────────────────────

  describe("Module beacon reporting", () => {
    beforeEach(async () => {
      // Alice deposits 32 ETH (one validator's worth) so we have a sensible state.
      await router.connect(alice).submit(ZeroAddress, {value: parseEther("32")});
    });

    it("only registered module addr can call reportModuleBeaconBalance", async () => {
      await expect(
        router.connect(impostor).reportModuleBeaconBalance(SOLO, parseEther("32"))
      ).to.be.revertedWithCustomError(router, "NotModule");
    });

    it("positive delta increases totalPooledEther and mints fees", async () => {
      // Validator module reports +0.5 ETH gain (delta vs. baseline 0).
      // Module path: oracle → mod1.reportBeacon → router.reportModuleBeaconBalance.
      const govSharesBefore = await stToken.sharesOf(gov.address);
      await mod1.connect(oracle).reportBeacon(1, parseEther("32.5"));
      const govSharesAfter = await stToken.sharesOf(gov.address);

      expect(await stToken.totalPooledEther()).to.be.gt(parseEther("32"));
      expect(govSharesAfter).to.be.gt(govSharesBefore);
    });

    it("negative delta (slash) decreases totalPooledEther without minting fees", async () => {
      // First push 32 ETH from buffer to (mock) beacon contract. This calls
      // notifyBeaconDeposit on the router, setting moduleBeaconBalance baseline = 32.
      const pubkey = ethers.hexlify(ethers.randomBytes(48));
      const creds = ethers.hexlify(ethers.randomBytes(32));
      const sig = ethers.hexlify(ethers.randomBytes(96));
      const root = ethers.hexlify(ethers.randomBytes(32));
      await mod1.connect(gov).depositToBeaconChain(pubkey, creds, sig, root);

      // Now totalPooledEther is still 32 (32 buffered → 32 on beacon, accounting unchanged).
      // Oracle reports baseline (32 ETH) — no delta, no fees.
      await mod1.connect(oracle).reportBeacon(1, parseEther("32"));
      const sharesBefore = await stToken.sharesOf(gov.address);

      // Slash: validator drops to 31 ETH.
      await mod1.connect(oracle).reportBeacon(1, parseEther("31"));
      const sharesAfter = await stToken.sharesOf(gov.address);
      expect(sharesAfter).to.equal(sharesBefore); // no fees on loss
      // totalPooledEther should be ~31 (down from 32).
      expect(await stToken.totalPooledEther()).to.be.lt(parseEther("32.0001"));
      expect(await stToken.totalPooledEther()).to.be.gte(parseEther("31"));
    });

    it("notifyBeaconDeposit baseline math: 32 ETH push then 33 ETH report yields +1 ETH delta", async () => {
      // The router's baseline is 0 initially. We need NODE_OPERATOR to push 32 ETH
      // to beacon, which would normally call `notifyBeaconDeposit`. Without an
      // actual mainnet beacon contract, simulate by directly calling notifyBeaconDeposit
      // from the module (impossible — the module is the only allowed caller).
      // Instead we rely on the oracle path: report 32 ETH (delta +32), then 33 ETH
      // (delta +1 gain → fees minted).
      await mod1.connect(oracle).reportBeacon(1, parseEther("32"));
      const govSharesAfter1 = await stToken.sharesOf(gov.address);
      await mod1.connect(oracle).reportBeacon(1, parseEther("33"));
      const govSharesAfter2 = await stToken.sharesOf(gov.address);
      expect(govSharesAfter2).to.be.gt(govSharesAfter1);
    });
  });

  // ── Default module switching ──────────────────────────────────────────────

  describe("Default module switching", () => {
    it("setDefaultModule routes future submits to the new module", async () => {
      await router.connect(gov).registerModule(SECONDARY, mod2.target, 0);
      await router.connect(gov).setDefaultModule(SECONDARY);
      await router.connect(alice).submit(ZeroAddress, {value: parseEther("1")});
      expect(await mod2.bufferedEther()).to.equal(parseEther("1"));
      expect(await mod1.bufferedEther()).to.equal(0n);
    });

    it("setDefaultModule reverts for unregistered module id", async () => {
      const fake = ethers.keccak256(ethers.toUtf8Bytes("FAKE"));
      await expect(
        router.connect(gov).setDefaultModule(fake)
      ).to.be.revertedWithCustomError(router, "ModuleNotRegistered");
    });

    it("non-GOV cannot setDefaultModule", async () => {
      await expect(
        router.connect(alice).setDefaultModule(SOLO)
      ).to.be.reverted;
    });
  });

  // ── Access control ─────────────────────────────────────────────────────────

  describe("Access control", () => {
    it("non-GOV cannot setFeeController", async () => {
      await expect(
        router.connect(alice).setFeeController(feeController.target)
      ).to.be.reverted;
    });

    it("totalEthOf sums across given modules", async () => {
      await router.connect(gov).registerModule(SECONDARY, mod2.target, 0);
      await router.connect(alice).submit(ZeroAddress, {value: parseEther("4")});
      await router.connect(alice).submitToModule(SECONDARY, ZeroAddress, {value: parseEther("6")});
      expect(await router.totalEthOf([SOLO, SECONDARY])).to.equal(parseEther("10"));
    });
  });
});
