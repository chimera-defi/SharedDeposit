import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";
import {ValidatorModule__factory, StakingRouter__factory} from "../../types";
import {ZeroAddress} from "ethers";

/**
 * Deploys the solo-validator ValidatorModule, registers it with the StakingRouter,
 * and sets it as the default route for `submit()` calls.
 *
 * Beacon-deposit-contract address is selected per-network:
 *   - mainnet  → 0x00000000219ab540356cBB839Cbe05303d7705Fa (canonical)
 *   - holesky  → 0x4242424242424242424242424242424242424242
 *   - hoodi    → 0x00000000219ab540356cBB839Cbe05303d7705Fa (Hoodi mirrors mainnet addr)
 *   - hardhat  → ZeroAddress (constructor falls back to mainnet default — tests
 *                supply their own MockBeaconDeposit and bypass this script).
 */
const SOLO_VALIDATOR_1 = "0x" + Buffer.from("SOLO_VALIDATOR_1").toString("hex").padEnd(64, "0");

function beaconDepositAddressFor(networkName: string): string {
  switch (networkName) {
    case "mainnet":
      return "0x00000000219ab540356cBB839Cbe05303d7705Fa";
    case "holesky":
      return "0x4242424242424242424242424242424242424242";
    case "hoodi":
      // Hoodi testnet uses the same address layout as mainnet.
      return "0x00000000219ab540356cBB839Cbe05303d7705Fa";
    default:
      // Hardhat / forks: pass zero so the contract falls back to the mainnet default.
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

  // Use a deterministic moduleId derived from a human-readable label so off-chain
  // tooling can compute it without needing a deployment artifact.
  const moduleId = hre.ethers.keccak256(hre.ethers.toUtf8Bytes("SOLO_VALIDATOR_1"));

  const {contract: validatorModule} = await deploy(ValidatorModule__factory, {
    from: accounts.deployer,
    args: [routerAddress, moduleId, gov, beaconDeposit],
    log: true,
  });

  // Register with the router. mintCapEth = 0 means unlimited (MVP); production
  // deployments should set a sane risk budget here.
  const router = await connect(StakingRouter__factory);
  const existing = await router.modules(moduleId);
  if (existing.addr === "0x0000000000000000000000000000000000000000") {
    console.log(`  Registering ValidatorModule (${moduleId}) with router...`);
    await router.connect(govSigner).registerModule(moduleId, validatorModule.target as string, 0);
    console.log("  Setting as default module...");
    await router.connect(govSigner).setDefaultModule(moduleId);
  }

  // Grant ORACLE role to gov as a placeholder. The OracleAdapter deployment
  // (009_oracleAdapter.ts) re-grants the role to the adapter contract.
  const ORACLE = await validatorModule.ORACLE();
  if (!(await validatorModule.hasRole(ORACLE, gov))) {
    console.log("  Granting ORACLE role to gov (placeholder)...");
    await validatorModule.connect(govSigner).grantRole(ORACLE, gov);
  }
};

export default func;
func.tags = ["modular-staking", "validator-module"];
func.dependencies = ["staking-router"];
