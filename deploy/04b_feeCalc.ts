import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {FeeCalc__factory} from "../types";
import {resolveGovernanceAddress} from "./helpers/governance";

/**
 *
 * This only needs to be deployed on testnets like sepolia which do not have a deposit contract.
 */
const func: DeployFunction = async hre => {
  const ship = await Ship.init(hre);
  const {deploy} = ship;
  const governance = await resolveGovernanceAddress(hre, ship);

  await deploy(FeeCalc__factory, {
    args: [
      {
        adminFee: 0,
        exitFee: 0,
        refundFeesOnWithdraw: false,
        chargeOnDeposit: true,
        chargeOnExit: false,
      },
      governance,
    ],
  });
};

export default func;
func.tags = ["feeCalc"];
func.dependencies = [];
