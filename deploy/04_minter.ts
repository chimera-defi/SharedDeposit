import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {SgETH, SgETH__factory, SharedDepositMinterV2__factory, WSGETH, WSGETH__factory} from "../types";
import {ZeroAddress} from "ethers";

const func: DeployFunction = async hre => {
  const {deploy, connect, accounts} = await Ship.init(hre);

  const sgEth = (await connect(SgETH__factory)) as SgETH;
  const wsgEth = (await connect(WSGETH__factory)) as WSGETH;

  const numValidators = 1000;
  const adminFee = 0;

  // const FeeCalc = await ethers.getContractFactory("FeeCalc");
  // const feeCalc = await FeeCalc.deploy(parseEther("0"), parseEther("0"));
  // await feeCalc.deployed();

  const addresses = [
    ZeroAddress,
    //feeCalc.address, // fee splitter
    sgEth.target, // sgETH address
    wsgEth.target, // wsgETH address
    accounts.multiSig.address, // government address
    ZeroAddress, // deposit contract address - can't find deposit contract - using dummy address
  ];

  const minter = await deploy(SharedDepositMinterV2__factory, {
    args: [numValidators, adminFee, addresses],
  });

  if (minter.newlyDeployed) {
    const tx = await sgEth.addMinter(minter.address);
    console.log("Adding minter role at", tx.hash);
    await tx.wait();
  }
};

export default func;
func.tags = ["minter"];
func.dependencies = ["sgEth", "wsgEth"];
