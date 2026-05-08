import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";
import {OracleAdapter__factory, ValidatorModule__factory} from "../../types";

/**
 * Deploys an OracleAdapter that points at the ValidatorModule (router-managed
 * staking). The adapter accepts sanity-checked beacon reports from authorized
 * SUBMITTERs and forwards them to `validatorModule.reportBeacon`.
 *
 * NOTE: The Phase-1 `006_oracleAdapter.ts` deploys an OracleAdapter pointing at
 * the legacy `StakingCore`. This script (009) is the Phase-2 router equivalent
 * — both can co-exist during migration. Choose one as the active reporting
 * surface depending on which staking surface is live.
 *
 * The adapter is granted the ORACLE role on the ValidatorModule so it can call
 * `reportBeacon`. Phase-1 placeholder ORACLE on gov (granted in 008) should be
 * revoked manually once 009 is in production.
 */
const func: DeployFunction = async hre => {
  const {deploy, connect, accounts, address} = await Ship.init(hre);

  const validatorModuleAddress = await address(ValidatorModule__factory);
  if (!validatorModuleAddress) throw new Error("ValidatorModule not deployed");

  const govSigner = accounts.multiSig ?? accounts.deployer;
  const gov = govSigner.address;

  const {contract: adapter} = await deploy(OracleAdapter__factory, {
    from: accounts.deployer,
    args: [validatorModuleAddress, gov],
    log: true,
    aliasName: "OracleAdapterValidator",
  });

  // Grant the OracleAdapter the ORACLE role on the ValidatorModule.
  const validatorModule = await connect(ValidatorModule__factory);
  const ORACLE = await validatorModule.ORACLE();
  const hasRole = await validatorModule.hasRole(ORACLE, adapter.target);
  if (!hasRole) {
    console.log("  Granting ORACLE role to OracleAdapter on ValidatorModule...");
    await validatorModule.connect(govSigner).grantRole(ORACLE, adapter.target as string);
  }

  // On non-mainnet networks, add deployer as SUBMITTER for testnet convenience.
  if (hre.network.name !== "mainnet") {
    const SUBMITTER = await adapter.SUBMITTER();
    if (!(await adapter.hasRole(SUBMITTER, accounts.deployer.address))) {
      console.log("  Adding deployer as SUBMITTER (testnet convenience)...");
      await adapter.connect(govSigner).addSubmitter(accounts.deployer.address);
    }
  }
};

export default func;
func.tags = ["modular-staking", "oracle-validator"];
func.dependencies = ["validator-module"];
