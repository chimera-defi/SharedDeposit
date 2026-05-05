import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {
  SgETH,
  SgETH__factory,
  SharedDepositMinterV2__factory,
  WSGETH,
  WSGETH__factory,
  DepositContract,
  DepositContract__factory,
  FeeCalc,
  FeeCalc__factory,
} from "../types";
import {ZeroHash} from "ethers";
import {resolveGovernanceAddress, resolveNodeOperatorAddress} from "./helpers/governance";

const func: DeployFunction = async hre => {
  const ship = await Ship.init(hre);
  const {deploy, connect, accounts} = ship;

  const sgEth = (await connect(SgETH__factory)) as SgETH;
  const wsgEth = (await connect(WSGETH__factory)) as WSGETH;
  const feeCalc = (await connect(FeeCalc__factory)) as FeeCalc;
  const governance = await resolveGovernanceAddress(hre, ship);
  const nodeOperator = resolveNodeOperatorAddress(governance);

  let chainId = await hre.getChainId();

  let depositContractAddr;
  if (chainId != "1") {
    let depositContract = (await connect(DepositContract__factory)) as DepositContract;
    depositContractAddr = depositContract.target;
  } else {
    depositContractAddr = "0x00000000219ab540356cBB839Cbe05303d7705Fa";
  }

  const numValidators = 1000;
  const adminFee = 0;

  // const FeeCalc = await ethers.getContractFactory("FeeCalc");
  // const feeCalc = await FeeCalc.deploy(parseEther("0"), parseEther("0"));
  // await feeCalc.deployed();

  const addresses = [
    // ZeroAddress,
    feeCalc.target, // fee splitter
    sgEth.target, // sgETH address
    wsgEth.target, // wsgETH address
    governance, // government address
    depositContractAddr, // deposit contract address - can't find deposit contract - using dummy address
    nodeOperator, // optional node operator address
  ];

  const minter = await deploy(SharedDepositMinterV2__factory, {
    args: [numValidators, adminFee, addresses],
  });

  if (minter.newlyDeployed) {
    const tx = await sgEth.addMinter(minter.address);
    console.log("Adding minter role at", tx.hash);
    await tx.wait();

    const deployerIsAdmin = await sgEth.hasRole(ZeroHash, accounts.deployer.address);
    if (deployerIsAdmin && governance.toLowerCase() !== accounts.deployer.address.toLowerCase()) {
      const ownTx = await sgEth.transferOwnership(governance);
      console.log("Transferring sgETH admin role at", ownTx.hash);
      await ownTx.wait();
    }
  }
};

export default func;
func.tags = ["minter"];
func.dependencies = ["sgEth", "wsgEth", "depositContract", "feeCalc"];
