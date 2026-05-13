/**
 * Fork test against mainnet beacon deposit contract.
 *
 * Requires MAINNET_RPC_URL env var (Alchemy/Infura/public endpoint).
 * Run with:
 *   MAINNET_RPC_URL=https://ethereum.publicnode.com \
 *   npx hardhat test test/v2/modular-staking/fork.spec.ts
 *
 * Strategy: inject MockBeaconDeposit bytecode at the canonical mainnet deposit
 * address (0x00000000219ab540356cBB839Cbe05303d7705Fa) so we can verify
 * our ETH-flow / access-control / credentials logic without needing valid
 * BLS deposit data.  We are testing _our_ contracts, not the deposit contract.
 *
 * Validates:
 *   1. ValidatorModule routes 32 ETH to the beacon deposit contract address
 *   2. Withdrawal-credentials enforcement fires before the external call
 *   3. ETH accounting is correct post-deposit
 *   4. DVTModule cluster-gating blocks unclustered deposits
 */
import {ethers} from "hardhat";
import {expect} from "chai";
import {parseEther, ZeroAddress} from "ethers";
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";

const SOLO  = ethers.keccak256(ethers.toUtf8Bytes("FORK_SOLO"));
const DVT_M = ethers.keccak256(ethers.toUtf8Bytes("FORK_DVT"));
const NODE_OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("NODE_OPERATOR"));

// Canonical mainnet beacon deposit contract — we'll shadow it with our mock.
const BEACON_DEPOSIT_CONTRACT = "0x00000000219ab540356cBB839Cbe05303d7705Fa";

const describeFork = process.env.MAINNET_RPC_URL ? describe : describe.skip;

describeFork("SharedStake V2 Fork (mainnet beacon deposit)", () => {
  let deployer: SignerWithAddress;
  let gov: SignerWithAddress;
  let alice: SignerWithAddress;
  let nodeOp: SignerWithAddress;

  let stToken: any;
  let router: any;
  let validatorModule: any;
  let dvtModule: any;
  let queue: any;

  before(async () => {
    [deployer, gov, alice, nodeOp] = await ethers.getSigners();

    // ── Shadow real beacon deposit with our mock ──────────────────────────
    // Deploy a mock to get its runtime bytecode, then copy it to the
    // canonical address so all deposits hit the mock.
    const MockBeaconDeposit = await ethers.getContractFactory("MockBeaconDeposit");
    const mockInstance = await MockBeaconDeposit.deploy();
    const mockCode = await ethers.provider.getCode(mockInstance.target);
    await ethers.provider.send("hardhat_setCode", [BEACON_DEPOSIT_CONTRACT, mockCode]);

    // ── Core contracts ────────────────────────────────────────────────────
    const StToken = await ethers.getContractFactory("StToken");
    stToken = await StToken.deploy();

    const StakingRouter = await ethers.getContractFactory("StakingRouter");
    router = await StakingRouter.deploy(stToken.target, gov.address);

    const WithdrawalQueueV2 = await ethers.getContractFactory("WithdrawalQueueV2");
    queue = await WithdrawalQueueV2.deploy(stToken.target, gov.address);

    const ValidatorModule = await ethers.getContractFactory("ValidatorModule");
    validatorModule = await ValidatorModule.deploy(
      router.target,
      SOLO,
      gov.address,
      BEACON_DEPOSIT_CONTRACT,
    );

    const DVTModule = await ethers.getContractFactory("DVTModule");
    dvtModule = await DVTModule.deploy(
      router.target,
      DVT_M,
      gov.address,
      BEACON_DEPOSIT_CONTRACT,
    );

    // ── Role wiring ───────────────────────────────────────────────────────
    await stToken.addMinter(router.target);
    await stToken.addMinter(queue.target);

    await router.connect(gov).registerModule(SOLO, validatorModule.target, 0);
    await router.connect(gov).registerModule(DVT_M, dvtModule.target, 0);
    await router.connect(gov).setDefaultModule(SOLO);

    await validatorModule.connect(gov).grantRole(NODE_OPERATOR_ROLE, gov.address);
    await dvtModule.connect(gov).grantRole(NODE_OPERATOR_ROLE, nodeOp.address);
  });

  // ── helpers ───────────────────────────────────────────────────────────
  function randDeposit() {
    return {
      pubkey:            ethers.hexlify(ethers.randomBytes(48)),
      withdrawalCreds:   ethers.hexlify(ethers.randomBytes(32)),
      signature:         ethers.hexlify(ethers.randomBytes(96)),
      depositDataRoot:   ethers.hexlify(ethers.randomBytes(32)),
    };
  }

  // ── Solo ValidatorModule fork tests ──────────────────────────────────

  it("routes 32 ETH from router to beacon deposit contract address", async () => {
    await router.connect(alice).submit(ZeroAddress, {value: parseEther("32")});
    expect(await validatorModule.bufferedEther()).to.equal(parseEther("32"));

    const beaconBefore = await ethers.provider.getBalance(BEACON_DEPOSIT_CONTRACT);
    const {pubkey, withdrawalCreds, signature, depositDataRoot} = randDeposit();

    await validatorModule.connect(gov).depositToBeaconChain(
      pubkey, withdrawalCreds, signature, depositDataRoot,
    );

    expect(await validatorModule.bufferedEther()).to.equal(0n);
    const beaconAfter = await ethers.provider.getBalance(BEACON_DEPOSIT_CONTRACT);
    expect(beaconAfter - beaconBefore).to.equal(parseEther("32"));
  });

  it("rejects deposit with invalid withdrawal credentials", async () => {
    await router.connect(alice).submit(ZeroAddress, {value: parseEther("32")});

    const expectedCreds = ethers.hexlify(ethers.randomBytes(32));
    await validatorModule.connect(gov).setExpectedWithdrawalCredentials(expectedCreds);

    const {pubkey, signature, depositDataRoot} = randDeposit();
    const badCreds = ethers.hexlify(ethers.randomBytes(32));

    await expect(
      validatorModule.connect(gov).depositToBeaconChain(pubkey, badCreds, signature, depositDataRoot),
    ).to.be.revertedWithCustomError(validatorModule, "InvalidWithdrawalCredentials");
  });

  it("accepts deposit when withdrawal credentials match expected", async () => {
    const expectedCreds = await validatorModule.expectedWithdrawalCredentials();
    const {pubkey, signature, depositDataRoot} = randDeposit();

    await expect(
      validatorModule.connect(gov).depositToBeaconChain(
        pubkey, expectedCreds, signature, depositDataRoot,
      ),
    ).to.not.be.reverted;

    expect(await validatorModule.bufferedEther()).to.equal(0n);
  });

  // ── DVTModule cluster-gating fork tests ──────────────────────────────

  it("DVTModule: blocks depositToBeaconChain when no cluster registered", async () => {
    await router.connect(alice).submitToModule(DVT_M, ZeroAddress, {value: parseEther("32")});

    const CLUSTER_ID = ethers.keccak256(ethers.toUtf8Bytes("cluster-1"));
    const {pubkey, withdrawalCreds, signature, depositDataRoot} = randDeposit();

    await expect(
      dvtModule.connect(nodeOp).depositToBeaconChainInCluster(
        CLUSTER_ID, pubkey, withdrawalCreds, signature, depositDataRoot,
      ),
    ).to.be.revertedWithCustomError(dvtModule, "ClusterNotActive");
  });

  it("DVTModule: allows deposit after cluster is registered", async () => {
    const CLUSTER_ID = ethers.keccak256(ethers.toUtf8Bytes("cluster-1"));
    const operators = [nodeOp.address, gov.address];
    await dvtModule.connect(gov).registerCluster(CLUSTER_ID, operators, 1);

    const {pubkey, withdrawalCreds, signature, depositDataRoot} = randDeposit();
    const beaconBefore = await ethers.provider.getBalance(BEACON_DEPOSIT_CONTRACT);

    await dvtModule.connect(nodeOp).depositToBeaconChainInCluster(
      CLUSTER_ID, pubkey, withdrawalCreds, signature, depositDataRoot,
    );

    const beaconAfter = await ethers.provider.getBalance(BEACON_DEPOSIT_CONTRACT);
    expect(beaconAfter - beaconBefore).to.equal(parseEther("32"));
  });

  it("DVTModule: deactivating a cluster blocks further deposits", async () => {
    await router.connect(alice).submitToModule(DVT_M, ZeroAddress, {value: parseEther("32")});

    const CLUSTER_ID = ethers.keccak256(ethers.toUtf8Bytes("cluster-1"));
    await dvtModule.connect(gov).deactivateCluster(CLUSTER_ID);

    const {pubkey, withdrawalCreds, signature, depositDataRoot} = randDeposit();
    await expect(
      dvtModule.connect(nodeOp).depositToBeaconChainInCluster(
        CLUSTER_ID, pubkey, withdrawalCreds, signature, depositDataRoot,
      ),
    ).to.be.revertedWithCustomError(dvtModule, "ClusterNotActive");
  });
});
