// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("../deploy_utils.js");
let {deployMinterV2, setWC, addMinter} = require("./lib/minter_deploy_utils.js");
let genParams = require("./lib/opts.js");
let OA = require("./lib/onchain_actions.js");

require("dotenv").config();

async function main() {
  deployer = new ethers.Wallet(network.name == "goerli" ? process.env.GOERLIPK : process.env.LOCALPK, ethers.provider);

  let dh = new DeployHelper(network.name, deployer.address);
  await dh.init(deployer.address, deployer);

  let oa = new OA(dh);
  let params = genParams(dh);

  /** Deploy core of v2 system
   * 1. Deploy sgETH
   * 2. Deploy wsgETH
   * 3. Deploy minter for sgETH - SharedDepositMinter
   * 3a. Add minter to sgETH
   */
  let sgETH = params.names.sgETH;
  await dh.deployContract(sgETH, sgETH, []);
  let sgETHAddrs = dh.addressOf(sgETH);
  params.sgETH = sgETHAddrs;

  let wsgETH = params.names.wsgETH;
  await dh.deployContract(wsgETH, wsgETH, [sgETHAddrs, params.epochLen]);
  let wsgETHAddr = dh.addressOf(wsgETH);
  params.wsgETH = wsgETHAddr;

  await deployMinterV2(dh, params);
  let minter = dh.addressOf(params.names.minter);
  params.minter = minter;

  await addMinter(dh, params);

  /**
   * Rewards and withdrawals processing system
   * 4. Deploy Dao payment splitter feeSplitter
   * 5. Deploy Withdrawals processing contract
   * 6. Deploy yield restaker - YieldDirector
   * 7. Deploy withdrawal pubkey - RewardsReceiver - recieves and routes all rewards and exits
   * 7a. Set the  RewardsReceiver as setWithdrawalCredential  on sgETH minter - SharedDepositMinter
   */

  // update dao fee splitter addresses
  params = genParams(dh, params);
  console.log(params.daoFeeSplitterDistro);

  // todo add node op and multisig to feesplitter / use custom instead of OZ generic
  await dh.deployContract("PaymentSplitter", "PaymentSplitter", [
    params.daoFeeSplitterDistro.addresses,
    params.daoFeeSplitterDistro.values,
  ]);
  // await dh.deployContract("FeeSplitter", "FeeSplitter", []);
  let feeSplitter = dh.addressOf("PaymentSplitter");

  await dh.deployContract("Withdrawals", "Withdrawals", [sgETHAddrs, params.sgETHVirtualPrice]);
  let withdrawals = dh.addressOf("Withdrawals");

  await dh.deployContract("YieldDirector", "YieldDirector", [sgETHAddrs, wsgETHAddr, feeSplitter, minter]);
  let converter = dh.addressOf("YieldDirector");

  await dh.deployContract("RewardsReceiver", "RewardsReceiver", [converter, withdrawals]);
  let rewardsReceiver = dh.addressOf("RewardsReceiver");
  params.rewardsReceiver = rewardsReceiver;

  // Set the withdrawal contract now that we have it - i.e the rewards recvr
  await setWC(dh, params);

  /**
   * Servicing for v1
   * 8. Deploy ETH Withdrawals processing contract for v1 veth2
   * 9. Deploy veth2 to sgETH rollover contract for v1
   */
  await dh.deployContract("WithdrawalsvETH2", "Withdrawals", [params.vETH2Addr, params.rolloverVirtual]);

  await dh.deployContract("Rollover", "Rollover", [params.vETH2Addr, sgETHAddrs, params.rolloverVirtual]);

  // Todo: ownership transfers
  // transferFeeSplittertoDao();

  // test deposit withdraw flow
  await oa.e2e(params);

  await dh.postRun();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
