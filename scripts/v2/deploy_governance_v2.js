/**
 * Deploy script for SharedStake V2 Governance:
 *   1. SGTv2 token (if not already deployed)
 *   2. VoteEscrowV2
 *   3. GovernanceTimelock
 *   4. SharedStakeGovernor
 *
 * Usage:
 *   npx hardhat run scripts/v2/deploy_governance_v2.js --network <network>
 */

const hre = require("hardhat");
const {parseEther} = hre.ethers;

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying V2 governance with account:", deployer.address);

  // ── 1. SGTv2 (reuse existing or deploy new) ──────────────────────────────
  let sgtv2Addr = process.env.SGT_V2_ADDRESS;
  if (!sgtv2Addr) {
    const SGTv2 = await hre.ethers.getContractFactory("SGTv2");
    const maxSupply = parseEther("10000000"); // 10M
    const sgt = await SGTv2.deploy("Sharedstake.finance", "SGT", maxSupply, deployer.address);
    await sgt.waitForDeployment();
    sgtv2Addr = await sgt.getAddress();
    console.log("SGTv2 deployed:", sgtv2Addr);
  } else {
    console.log("Using existing SGTv2:", sgtv2Addr);
  }

  // ── 2. VoteEscrowV2 ──────────────────────────────────────────────────────
  const VoteEscrowV2 = await hre.ethers.getContractFactory("VoteEscrowV2");
  const veSGT = await VoteEscrowV2.deploy(
    "Vote Escrowed SGT",
    "veSGT",
    sgtv2Addr,
    parseEther("10"), // minLockedAmount: 10 SGT
    deployer.address    // initial gov
  );
  await veSGT.waitForDeployment();
  const veSGTAddr = await veSGT.getAddress();
  console.log("VoteEscrowV2 deployed:", veSGTAddr);

  // ── 3. GovernanceTimelock ────────────────────────────────────────────────
  // 48-hour delay. deployer is temporary admin; will be transferred to Governor.
  const minDelay = 2 * 24 * 60 * 60; // 48 hours
  const GovernanceTimelock = await hre.ethers.getContractFactory("GovernanceTimelock");
  const timelock = await GovernanceTimelock.deploy(minDelay, [deployer.address], [deployer.address]);
  await timelock.waitForDeployment();
  const timelockAddr = await timelock.getAddress();
  console.log("GovernanceTimelock deployed:", timelockAddr);

  // ── 4. SharedStakeGovernor ───────────────────────────────────────────────
  const SharedStakeGovernor = await hre.ethers.getContractFactory("SharedStakeGovernor");
  const governor = await SharedStakeGovernor.deploy(veSGTAddr, timelockAddr);
  await governor.waitForDeployment();
  const governorAddr = await governor.getAddress();
  console.log("SharedStakeGovernor deployed:", governorAddr);

  // ── 5. Post-deployment wiring ────────────────────────────────────────────
  // Grant PROPOSER and EXECUTOR roles to Governor on timelock
  const PROPOSER_ROLE = await timelock.PROPOSER_ROLE();
  const EXECUTOR_ROLE = await timelock.EXECUTOR_ROLE();
  const CANCELLER_ROLE = await timelock.CANCELLER_ROLE();

  await (await timelock.grantRole(PROPOSER_ROLE, governorAddr)).wait();
  await (await timelock.grantRole(EXECUTOR_ROLE, governorAddr)).wait();
  await (await timelock.grantRole(CANCELLER_ROLE, governorAddr)).wait();

  // Transfer VoteEscrowV2 gov to timelock
  await (await veSGT.transferGov(timelockAddr)).wait();

  // Renounce deployer's DEFAULT_ADMIN_ROLE on timelock
  const DEFAULT_ADMIN_ROLE = await timelock.DEFAULT_ADMIN_ROLE();
  await (await timelock.renounceRole(DEFAULT_ADMIN_ROLE, deployer.address)).wait();

  console.log("\n=== V2 Governance Deployment Complete ===");
  console.log("SGTv2:            ", sgtv2Addr);
  console.log("VoteEscrowV2:     ", veSGTAddr);
  console.log("GovernanceTimelock:", timelockAddr);
  console.log("SharedStakeGovernor:", governorAddr);
  console.log("\nNext steps:");
  console.log("1. Transfer protocol contract GOV roles to timelock");
  console.log("2. Add veSGT to frontend address book");
  console.log("3. Update AGENTS.md / handoff with new addresses");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
