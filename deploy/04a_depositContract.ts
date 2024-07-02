import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {DepositContract__factory} from "../types";

/**
 * 
 * This only needs to be deployed on testnets like sepolia which do not have a deposit contract. 
 * Do not deploy on mainnet
 */
const func: DeployFunction = async hre => {
  const {deploy} = await Ship.init(hre);

  const dc = await deploy(DepositContract__factory, {
    args: [],
  });
};

export default func;
func.tags = ["depositContract"];
func.dependencies = [];
