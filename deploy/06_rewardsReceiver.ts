import {DeployFunction} from "hardhat-deploy/types";
import Ship from "../utils/ship";
import {
  PaymentSplitter,
  PaymentSplitter__factory,
  RewardsReceiver,
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

function makeWithdrawalCred(params: any) {
  // see https://github.com/ethereum/consensus-specs/pull/2149/files & https://github.com/stakewise/contracts/blob/0e51a35e58676491060df84d665e7ebb0e735d17/test/pool/depositDataMerkleRoot.js#L140
  // pubkey is 0x01 + (11 bytes?) 20 0s + eth1 addr 20 bytes (40 characters)  ? = final length 66
  //
  let withdrawalCredsPrefix = `0x010000000000000000000000`;
  let eth1Withdraw = `${withdrawalCredsPrefix}${params.split("x")[1]}`;
  console.log(`setWithdrawalCredential ${eth1Withdraw}`);

  return eth1Withdraw;
}


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

  let rr =  (await connect(RewardsReceiver__factory)) as RewardsReceiver;
  await minter.setWithdrawalCredential(makeWithdrawalCred(rr.target));
};

export default func;
func.tags = ["rewardsReceiver"];
func.dependencies = ["sgEth", "wsgEth", "paymentSplitter", "minter", "withdrawalQueue"];
