import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {
  SharedDepositMinterV2,
  SharedDepositMinterV2__factory,
  WSGETH,
  WSGETH__factory,
  WithdrawalQueue__factory,
} from "../types";
import {resolveGovernanceAddress} from "./helpers/governance";

const func: DeployFunction = async hre => {
  const ship = await Ship.init(hre);
  const {deploy, connect} = ship;

  const wsgEth = (await connect(WSGETH__factory)) as WSGETH;
  const minter = (await connect(SharedDepositMinterV2__factory)) as SharedDepositMinterV2;
  const governance = await resolveGovernanceAddress(hre, ship);

  const epoch = 1; // 1 block for quick tests

  await deploy(WithdrawalQueue__factory, {
    args: [minter.target, wsgEth.target, epoch, governance],
  });
};

export default func;
func.tags = ["withdrawalQueue"];
func.dependencies = ["minter", "wsgEth"];
