/**
 * Fork test against mainnet beacon deposit contract.
 *
 * Requires MAINNET_RPC_URL env var to be set (Alchemy/Infura).
 * Run with:
 *   MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/xxx \
 *   npx hardhat test test/v2/modular-staking/fork.spec.ts --fork
 *
 * Validates:
 *   1. ValidatorModule can deposit to the real beacon deposit contract
 *   2. Deposit data is correctly formatted
 *   3. ETH balance moves from module to deposit contract
 */
import {ethers} from "hardhat";
import {expect} from "chai";
import {parseEther, ZeroAddress} from "ethers";
import {SignerWithAddress} from "@nomicfoundation/hardhat-ethers/signers";

const SOLO = ethers.keccak256(ethers.toUtf8Bytes("FORK_SOLO"));
const NODE_OPERATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("NODE_OPERATOR"));

// Mainnet beacon deposit contract
const BEACON_DEPOSIT_CONTRACT = "0x00000000219ab540356cBB839Cbe05303d7705Fa";

// Skip if no mainnet RPC is configured
const describeFork = process.env.MAINNET_RPC_URL ? describe : describe.skip;

describeFork("SharedStake V2 Fork (mainnet beacon deposit)", () => {
  let deployer: SignerWithAddress;
  let gov: SignerWithAddress;
  let alice: SignerWithAddress;

  let stToken: any;
  let router: any;
  let validatorModule: any;
  let queue: any;

  before(async () => {
    [deployer, gov, alice] = await ethers.getSigners();

    // Deploy contracts
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
      BEACON_DEPOSIT_CONTRACT, // real mainnet deposit contract
    );

    // Wire
    await stToken.addMinter(router.target);
    await stToken.addMinter(queue.target);
    await router.connect(gov).registerModule(SOLO, validatorModule.target, 0);
    await router.connect(gov).setDefaultModule(SOLO);
    await validatorModule.connect(gov).grantRole(NODE_OPERATOR_ROLE, gov.address);
  });

  it("deposits ETH to the real beacon deposit contract", async () => {
    // Alice deposits 32 ETH
    await router.connect(alice).submit(ZeroAddress, {value: parseEther("32")});

    // Module buffers 32 ETH
    expect(await validatorModule.bufferedEther()).to.equal(parseEther("32"));

    // Prepare validator deposit data
    const pubkey = ethers.hexlify(ethers.randomBytes(48));
    const withdrawalCreds = ethers.hexlify(ethers.randomBytes(32));
    const signature = ethers.hexlify(ethers.randomBytes(96));
    const depositDataRoot = ethers.hexlify(ethers.randomBytes(32));

    // Beacon deposit contract balance before
    const beaconBalanceBefore = await ethers.provider.getBalance(BEACON_DEPOSIT_CONTRACT);

    // Deposit to beacon chain
    await validatorModule.connect(gov).depositToBeaconChain(
      pubkey,
      withdrawalCreds,
      signature,
      depositDataRoot,
    );

    // Module buffer is now 0
    expect(await validatorModule.bufferedEther()).to.equal(0n);

    // Beacon deposit contract received 32 ETH
    const beaconBalanceAfter = await ethers.provider.getBalance(BEACON_DEPOSIT_CONTRACT);
    expect(beaconBalanceAfter - beaconBalanceBefore).to.equal(parseEther("32"));

    // Module beacon balance is 32
    expect(await validatorModule.beaconBalance()).to.equal(0n); // not yet reported
    expect(await router.moduleBeaconBalance(SOLO)).to.equal(parseEther("32"));
  });

  it("rejects deposit with invalid withdrawal credentials", async () => {
    // Top up buffer
    await router.connect(alice).submit(ZeroAddress, {value: parseEther("32")});

    // Set expected withdrawal credentials
    const expectedCreds = ethers.hexlify(ethers.randomBytes(32));
    await validatorModule.connect(gov).setExpectedWithdrawalCredentials(expectedCreds);

    const pubkey = ethers.hexlify(ethers.randomBytes(48));
    const badCreds = ethers.hexlify(ethers.randomBytes(32)); // different from expected
    const signature = ethers.hexlify(ethers.randomBytes(96));
    const depositDataRoot = ethers.hexlify(ethers.randomBytes(32));

    await expect(
      validatorModule.connect(gov).depositToBeaconChain(pubkey, badCreds, signature, depositDataRoot),
    ).to.be.revertedWithCustomError(validatorModule, "InvalidWithdrawalCredentials");
  });

  it("accepts deposit with matching withdrawal credentials", async () => {
    // Use correct credentials
    const expectedCreds = await validatorModule.expectedWithdrawalCredentials();
    const pubkey = ethers.hexlify(ethers.randomBytes(48));
    const signature = ethers.hexlify(ethers.randomBytes(96));
    const depositDataRoot = ethers.hexlify(ethers.randomBytes(32));

    await expect(
      validatorModule.connect(gov).depositToBeaconChain(pubkey, expectedCreds, signature, depositDataRoot),
    ).to.not.be.reverted;
  });
});
