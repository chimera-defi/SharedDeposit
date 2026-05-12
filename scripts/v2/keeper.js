/**
 * SharedStake V2 Keeper Scripts
 *
 * Operational automation for:
 *   1. Beacon deposits — push buffered ETH to beacon chain when 32 ETH available
 *   2. Oracle reports — submit beacon balance updates
 *   3. Withdrawal finalization — finalize withdrawal requests with ETH
 *
 * Usage:
 *   npx hardhat run scripts/v2/keeper.js --network localhost
 *
 * Environment:
 *   KEEPER_PRIVATE_KEY    — keeper wallet private key
 *   STAKING_ROUTER_ADDR   — deployed StakingRouter address
 *   VALIDATOR_MODULE_ADDR — deployed ValidatorModule address
 *   WITHDRAWAL_QUEUE_ADDR — deployed WithdrawalQueueV2 address
 *   ORACLE_ADAPTER_ADDR   — deployed OracleAdapter address
 *   BEACON_RPC_URL        — beacon node RPC (e.g. Lighthouse/Prysm)
 */

const hre = require("hardhat");
const {parseEther, ZeroAddress} = hre.ethers;

// ── Config (override via env) ──────────────────────────────────────────────
const ROUTER_ADDR = process.env.STAKING_ROUTER_ADDR;
const MODULE_ADDR = process.env.VALIDATOR_MODULE_ADDR;
const QUEUE_ADDR = process.env.WITHDRAWAL_QUEUE_ADDR;
const ORACLE_ADAPTER_ADDR = process.env.ORACLE_ADAPTER_ADDR;
const BEACON_RPC = process.env.BEACON_RPC_URL || "http://localhost:5052";

// ── Helpers ────────────────────────────────────────────────────────────────

async function getContracts() {
  const router = await hre.ethers.getContractAt("StakingRouter", ROUTER_ADDR);
  const module = await hre.ethers.getContractAt("ValidatorModule", MODULE_ADDR);
  const queue = await hre.ethers.getContractAt("WithdrawalQueueV2", QUEUE_ADDR);
  const oracleAdapter = ORACLE_ADAPTER_ADDR
    ? await hre.ethers.getContractAt("OracleAdapter", ORACLE_ADAPTER_ADDR)
    : null;
  return {router, module, queue, oracleAdapter};
}

async function getBeaconBalance() {
  try {
    const resp = await fetch(`${BEACON_RPC}/eth/v1/beacon/states/head/validator_balances`);
    const data = await resp.json();
    // Sum all validator balances (in Gwei)
    const totalGwei = data.data.reduce((sum, v) => sum + BigInt(v.balance), 0n);
    return totalGwei * 10n ** 9n; // convert to wei
  } catch (e) {
    console.error("Failed to fetch beacon balance:", e.message);
    return null;
  }
}

async function getBeaconValidatorCount() {
  try {
    const resp = await fetch(`${BEACON_RPC}/eth/v1/beacon/states/head/validators`);
    const data = await resp.json();
    return data.data.filter(v => v.status === "active_ongoing").length;
  } catch (e) {
    console.error("Failed to fetch validator count:", e.message);
    return null;
  }
}

// ── Tasks ──────────────────────────────────────────────────────────────────

async function depositToBeacon() {
  if (!ROUTER_ADDR || !MODULE_ADDR) {
    console.log("SKIP: STAKING_ROUTER_ADDR or VALIDATOR_MODULE_ADDR not set");
    return;
  }

  const {module} = await getContracts();
  const buffered = await module.bufferedEther();
  const depositAmount = parseEther("32");

  if (buffered < depositAmount) {
    console.log(`Buffer: ${hre.ethers.formatEther(buffered)} ETH < 32 ETH, skipping deposit`);
    return;
  }

  const validators = Number(buffered / depositAmount);
  console.log(`Buffer: ${hre.ethers.formatEther(buffered)} ETH → can deposit ${validators} validators`);

  // In production, load validator keys from secure key management (e.g. Dirk, Web3Signer)
  // This example uses dummy data for demonstration.
  for (let i = 0; i < validators; i++) {
    const pubkey = hre.ethers.hexlify(hre.ethers.randomBytes(48));
    const creds = hre.ethers.hexlify(hre.ethers.randomBytes(32));
    const sig = hre.ethers.hexlify(hre.ethers.randomBytes(96));
    const root = hre.ethers.hexlify(hre.ethers.randomBytes(32));

    try {
      const tx = await module.depositToBeaconChain(pubkey, creds, sig, root);
      await tx.wait();
      console.log(`✓ Deposited validator ${i + 1}/${validators}: ${tx.hash}`);
    } catch (e) {
      console.error(`✗ Failed to deposit validator ${i + 1}:`, e.message);
      break;
    }
  }
}

async function submitOracleReport() {
  if (!ORACLE_ADAPTER_ADDR || !MODULE_ADDR) {
    console.log("SKIP: ORACLE_ADAPTER_ADDR or VALIDATOR_MODULE_ADDR not set");
    return;
  }

  const {module, oracleAdapter} = await getContracts();
  const validatorCount = await getBeaconValidatorCount();
  const beaconBalance = await getBeaconBalance();

  if (validatorCount === null || beaconBalance === null) {
    console.log("SKIP: Could not fetch beacon data");
    return;
  }

  const currentValidators = await module.beaconValidators();
  if (currentValidators === 0n && validatorCount === 0) {
    console.log("No validators deposited yet, skipping report");
    return;
  }

  const timestamp = Math.floor(Date.now() / 1000);
  console.log(`Submitting report: ${validatorCount} validators, ${hre.ethers.formatEther(beaconBalance)} ETH`);

  try {
    // Get submitter address (must have SUBMITTER role)
    const [signer] = await hre.ethers.getSigners();
    const tx = await oracleAdapter.connect(signer).submitReport(validatorCount, beaconBalance, timestamp);
    await tx.wait();
    console.log(`✓ Oracle report submitted: ${tx.hash}`);
  } catch (e) {
    console.error("✗ Failed to submit oracle report:", e.message);
  }
}

async function finalizeWithdrawals() {
  if (!QUEUE_ADDR) {
    console.log("SKIP: WITHDRAWAL_QUEUE_ADDR not set");
    return;
  }

  const {queue} = await getContracts();
  const nextId = await queue.nextRequestId();
  const lastFinalized = await queue.lastFinalizedRequestId();

  if (lastFinalized + 1n >= nextId) {
    console.log("No pending withdrawals to finalize");
    return;
  }

  // Compute required ETH for all pending requests
  let required = 0n;
  const fromId = Number(lastFinalized) + 1;
  const toId = Number(nextId) - 1;

  for (let i = fromId; i <= toId; i++) {
    const req = await queue.getRequest(i);
    if (!req.finalized) {
      required += req.ethAmount;
    }
  }

  if (required === 0n) {
    console.log("No unfinalized withdrawals");
    return;
  }

  const [signer] = await hre.ethers.getSigners();
  const signerBalance = await hre.ethers.provider.getBalance(signer.address);

  if (signerBalance < required) {
    console.log(`Insufficient balance: ${hre.ethers.formatEther(signerBalance)} < ${hre.ethers.formatEther(required)}`);
    return;
  }

  console.log(`Finalizing requests ${fromId}–${toId}, need ${hre.ethers.formatEther(required)} ETH`);

  try {
    const tx = await queue.connect(signer).finalize(toId, {value: required});
    await tx.wait();
    console.log(`✓ Finalized: ${tx.hash}`);
  } catch (e) {
    console.error("✗ Failed to finalize:", e.message);
  }
}

// ── Main ───────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════");
  console.log("  SharedStake V2 Keeper");
  console.log("═══════════════════════════════════════════");
  console.log("");

  await depositToBeacon();
  console.log("");

  await submitOracleReport();
  console.log("");

  await finalizeWithdrawals();
  console.log("");

  console.log("Keeper run complete.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
