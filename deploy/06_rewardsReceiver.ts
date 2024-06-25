import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {
  PaymentSplitter,
  PaymentSplitter__factory,
  RewardsReceiver__factory,
  SgETH,
  SgETH__factory,
  SharedDepositMinterV2,
  SharedDepositMinterV2__factory,
  WSGETH,
  WSGETH__factory,
  WithdrawalQueue,
  WithdrawalQueue__factory,
} from "../types";

const func: DeployFunction = async hre => {
  const {deploy, connect} = await Ship.init(hre);

  const sgEth = (await connect(SgETH__factory)) as SgETH;
  const wsgEth = (await connect(WSGETH__factory)) as WSGETH;
  const paymentSplitter = (await connect(PaymentSplitter__factory)) as PaymentSplitter;
  const minter = (await connect(SharedDepositMinterV2__factory)) as SharedDepositMinterV2;
  const withdrawalQueue = (await connect(WithdrawalQueue__factory)) as WithdrawalQueue;

  await deploy(RewardsReceiver__factory, {
    args: [withdrawalQueue.target, [sgEth.target, wsgEth.target, paymentSplitter.target, minter.target]],
  });
};

export default func;
func.tags = ["rewardsReceiver"];
func.dependencies = ["sgEth", "wsgEth", "paymentSplitter", "minter", "withdrawalQueue"];
