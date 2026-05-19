import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";
import {FeeController__factory} from "../../types";
import {resolveGovernanceAddress, resolveOperatorAddress} from "../helpers/governance";

const func: DeployFunction = async hre => {
  const ship = await Ship.init(hre);
  const {deploy, accounts} = ship;

  const gov = await resolveGovernanceAddress(hre, ship);
  const treasury = gov; // governance recipient (multisig when configured)
  const operator = resolveOperatorAddress(hre, gov);
  const referralRegistry = hre.ethers.ZeroAddress; // no referral registry on local
  const feeBps = 1000;         // 10% total protocol fee
  const treasurySplitBps = 5000; // 50% to treasury
  const operatorSplitBps = 5000; // 50% to operator

  await deploy(FeeController__factory, {
    from: accounts.deployer,
    args: [gov, treasury, operator, referralRegistry, feeBps, treasurySplitBps, operatorSplitBps],
    log: true,
  });
};

export default func;
func.tags = ["modular-staking", "feeController"];
