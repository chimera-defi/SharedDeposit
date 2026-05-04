import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";
import {StakingCore__factory, StToken__factory, FeeController__factory} from "../../types";

const func: DeployFunction = async hre => {
  const {deploy, connect, accounts, address} = await Ship.init(hre);

  const stTokenAddress = await address(StToken__factory);
  if (!stTokenAddress) throw new Error("StToken not deployed");

  const gov = accounts.multiSig.address;

  const {contract: stakingCore} = await deploy(StakingCore__factory, {
    from: accounts.deployer,
    args: [stTokenAddress, gov],
    log: true,
  });

  // Grant StakingCore MINTER role on StToken so it can mint/burn shares.
  const stToken = await connect(StToken__factory);
  const MINTER = await stToken.MINTER();

  const hasRole = await stToken.hasRole(MINTER, stakingCore.target);
  if (!hasRole) {
    console.log("  Granting MINTER role to StakingCore...");
    await stToken.connect(accounts.deployer).addMinter(stakingCore.target as string);
  }

  // Wire FeeController if deployed.
  const feeControllerAddress = await address(FeeController__factory);
  if (feeControllerAddress) {
    console.log("  Setting FeeController on StakingCore...");
    const ORACLE = await stakingCore.ORACLE();
    // Grant GOV role to multiSig so it can call setFeeController.
    // setFeeController requires GOV role; GOV was granted to multiSig in constructor.
    await stakingCore.connect(accounts.multiSig).setFeeController(feeControllerAddress);
  }
};

export default func;
func.tags = ["lido-parity", "stakingCore"];
func.dependencies = ["stToken", "feeController"];
