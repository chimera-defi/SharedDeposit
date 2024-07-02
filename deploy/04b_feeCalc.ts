import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {FeeCalc__factory} from "../types";

/**
 * 
 * This only needs to be deployed on testnets like sepolia which do not have a deposit contract. 
 */
const func: DeployFunction = async hre => {
  const {deploy} = await Ship.init(hre);

  const fc = await deploy(FeeCalc__factory, {
    args: [{
        adminFee : 10,
        exitFee : 0,
        refundFeesOnWithdraw : true,
        chargeOnDeposit : true,
        chargeOnExit : false,
    }],
  });
};

export default func;
func.tags = ["feeCalc"];
func.dependencies = [];
