import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";
import {OracleAdapter__factory, StakingCore__factory} from "../../types";

const func: DeployFunction = async hre => {
  const {deploy, connect, accounts, address} = await Ship.init(hre);

  const stakingCoreAddress = await address(StakingCore__factory);
  if (!stakingCoreAddress) throw new Error("StakingCore not deployed");

  const govSigner = accounts.multiSig ?? accounts.deployer;
  const gov = govSigner.address;

  const {contract: oracle} = await deploy(OracleAdapter__factory, {
    from: accounts.deployer,
    args: [stakingCoreAddress, gov],
    log: true,
  });

  // Grant OracleAdapter the ORACLE role on StakingCore so it can call reportBeacon.
  const stakingCore = await connect(StakingCore__factory);
  const ORACLE = await stakingCore.ORACLE();

  const hasRole = await stakingCore.hasRole(ORACLE, oracle.target);
  if (!hasRole) {
    console.log("  Granting ORACLE role to OracleAdapter...");
    await stakingCore.connect(govSigner).grantRole(ORACLE, oracle.target as string);
  }

  // Add deployer as initial oracle submitter for testnet convenience.
  if (hre.network.name !== "mainnet") {
    const SUBMITTER = await oracle.SUBMITTER();
    const submitterHasRole = await oracle.hasRole(SUBMITTER, accounts.deployer.address);
    if (!submitterHasRole) {
      console.log("  Adding deployer as SUBMITTER on OracleAdapter...");
      await oracle.connect(govSigner).addSubmitter(accounts.deployer.address);
    }
  }
};

export default func;
func.tags = ["modular-staking", "oracleAdapter"];
func.dependencies = ["stakingCore"];
