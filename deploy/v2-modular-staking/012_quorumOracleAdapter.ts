import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";
import {QuorumOracleAdapter__factory, ValidatorModule__factory} from "../../types";

/**
 * Deploys QuorumOracleAdapter as an ALTERNATIVE oracle path (not replacing
 * the single-submitter OracleAdapter). Ops can choose which adapter to wire
 * as the active ORACLE on ValidatorModule/DVTModule.
 *
 * Default: quorum = 2, submitters = [deployer] (testnet convenience).
 * For mainnet: set quorum >= 2 and add >= 3 independent submitters.
 */
const func: DeployFunction = async hre => {
  const {deploy, connect, accounts, address} = await Ship.init(hre);

  const validatorModuleAddress = await address(ValidatorModule__factory);
  if (!validatorModuleAddress) throw new Error("ValidatorModule not deployed");

  const govSigner = accounts.multiSig ?? accounts.deployer;
  const gov = govSigner.address;

  const {contract: adapter} = await deploy(QuorumOracleAdapter__factory, {
    from: accounts.deployer,
    args: [validatorModuleAddress, gov, 2], // quorum = 2
    log: true,
    aliasName: "QuorumOracleAdapter",
  });

  // Grant QuorumOracleAdapter the ORACLE role on ValidatorModule.
  const validatorModule = await connect(ValidatorModule__factory);
  const ORACLE = await validatorModule.ORACLE();
  const hasRole = await validatorModule.hasRole(ORACLE, adapter.target);
  if (!hasRole) {
    console.log("  Granting ORACLE role to QuorumOracleAdapter on ValidatorModule...");
    await validatorModule.connect(govSigner).grantRole(ORACLE, adapter.target as string);
  }

  // Testnet convenience: add deployer as initial submitter.
  if (hre.network.name !== "mainnet") {
    const SUBMITTER = await adapter.SUBMITTER();
    if (!(await adapter.hasRole(SUBMITTER, accounts.deployer.address))) {
      console.log("  Adding deployer as SUBMITTER (testnet convenience)...");
      await adapter.connect(govSigner).addSubmitter(accounts.deployer.address);
    }
  }
};

export default func;
func.tags = ["modular-staking", "quorum-oracle"];
func.dependencies = ["validator-module"];
