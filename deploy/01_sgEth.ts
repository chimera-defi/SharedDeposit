import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {SgETH__factory} from "../types";

const func: DeployFunction = async hre => {
  const {deploy} = await Ship.init(hre);

  await deploy(SgETH__factory);
};

export default func;
func.tags = ["sgEth"];
