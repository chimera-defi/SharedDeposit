import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {PaymentSplitter__factory, WSGETH, WSGETH__factory} from "../types";

const func: DeployFunction = async hre => {
  const {deploy, connect, accounts} = await Ship.init(hre);

  const wsgEth = (await connect(WSGETH__factory)) as WSGETH;

  const splitterAddresses = [accounts.deployer.address, accounts.multiSig.address, wsgEth.target];
  const splitterValues = [6, 3, 31];

  await deploy(PaymentSplitter__factory, {
    args: [splitterAddresses, splitterValues],
  });
};

export default func;
func.tags = ["paymentSplitter"];
func.dependencies = ["wsgEth"];
