import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../../utils/ship";
import {FeeController__factory} from "../../types";

const func: DeployFunction = async hre => {
  const {deploy, accounts} = await Ship.init(hre);

  const govSigner = accounts.multiSig ?? accounts.deployer;
  const gov = govSigner.address;
  const treasury = gov; // governance recipient (multisig when configured)
  const operator = accounts.deployer.address;
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
