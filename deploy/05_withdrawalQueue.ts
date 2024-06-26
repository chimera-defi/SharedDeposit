import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {
  SharedDepositMinterV2,
  SharedDepositMinterV2__factory,
  WSGETH,
  WSGETH__factory,
  WithdrawalQueue__factory,
} from "../types";

const func: DeployFunction = async hre => {
  const {deploy, connect} = await Ship.init(hre);

  const wsgEth = (await connect(WSGETH__factory)) as WSGETH;
  const minter = (await connect(SharedDepositMinterV2__factory)) as SharedDepositMinterV2;

  const epoch = 1; // 1 block for quick tests

  await deploy(WithdrawalQueue__factory, {
    args: [minter.target, wsgEth.target, epoch],
  });
};

export default func;
func.tags = ["withdrawalQueue"];
func.dependencies = ["minter", "wsgEth"];
