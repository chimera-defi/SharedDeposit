import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";
import {DVTModule__factory, StakingRouter__factory} from "../../types";
import {ZeroAddress} from "ethers";

/**
 * Deploys the DVTModule (Distributed Validator Technology variant).
 * Mirrors the ValidatorModule deploy but uses DVTModule contract and
 * DVT_VALIDATOR_1 moduleId. Does NOT set as default (solo validator remains default).
 *
 * Cluster-coordinator hooks (operator whitelist, threshold-sig pre-flight)
 * are deferred to Phase 2; this script deploys the minimal skeleton.
 */
const DVT_VALIDATOR_1 = "0x" + Buffer.from("DVT_VALIDATOR_1").toString("hex").padEnd(64, "0");

function beaconDepositAddressFor(networkName: string): string {
  switch (networkName) {
    case "mainnet":
      return "0x00000000219ab540356cBB839Cbe05303d7705Fa";
    case "holesky":
      return "0x4242424242424242424242424242424242424242";
    case "hoodi":
      return "0x00000000219ab540356cBB839Cbe05303d7705Fa";
    default:
      return ZeroAddress;
  }
}

const func: DeployFunction = async hre => {
  const {deploy, connect, accounts, address, hre: hardhat} = await Ship.init(hre);
  const networkName = hardhat.network.name;

  const routerAddress = await address(StakingRouter__factory);
  if (!routerAddress) throw new Error("StakingRouter not deployed");

  const govSigner = accounts.multiSig ?? accounts.deployer;
  const gov = govSigner.address;
  const beaconDeposit = beaconDepositAddressFor(networkName);

  const moduleId = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("DVT_VALIDATOR_1"));

  const {contract: dvtModule} = await deploy(DVTModule__factory, {
    from: accounts.deployer,
    args: [routerAddress, moduleId, gov, beaconDeposit],
    log: true,
  });

  const router = await connect(StakingRouter__factory);
  const existing = await router.modules(moduleId);
  if (existing.addr === "0x0000000000000000000000000000000000000000") {
    console.log(`  Registering DVTModule (${moduleId}) with router...`);
    // mintCapEth = 0 means unlimited for now; production should set a cap.
    await router.connect(govSigner).registerModule(moduleId, dvtModule.target as string, 0);
  }

  // Grant ORACLE role placeholder (QuorumOracleAdapter deploy will re-grant).
  const ORACLE = await dvtModule.ORACLE();
  if (!(await dvtModule.hasRole(ORACLE, gov))) {
    console.log("  Granting ORACLE role to gov (placeholder)...");
    await dvtModule.connect(govSigner).grantRole(ORACLE, gov);
  }
};

export default func;
func.tags = ["modular-staking", "dvt-module"];
func.dependencies = ["staking-router"];
