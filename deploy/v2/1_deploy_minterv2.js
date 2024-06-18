// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("../deploy_utils.js");
let {deployMinterV2, setWC, addMinter} = require("./lib/minter_deploy_utils.js");
let genParams = require("./lib/opts.js");
let OA = require("./lib/onchain_actions.js");

require("dotenv").config();

async function main() {
  pk = ''
  if (network.name == "goerli") {
    pk = process.env.GOERLIPK;
  } else if (network.name == "sepolia") {
    pk = process.env.SEPOLIAPK;
  } else {
    pk = process.env.LOCALPK;
  }
  deployer = new ethers.Wallet(pk);

  let dh = new DeployHelper(network.name, deployer.address);
  await dh.init(deployer.address, deployer);

  let oa = new OA(dh);
  let params = genParams(dh);
  dh.multisig_address = params.multisigAddr;

  /** Deploy core of v2 system
   * 1. Deploy sgETH
   * 2. Deploy wsgETH
   * 3. Deploy minter for sgETH - SharedDepositMinterV2
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

  await dh.waitIfNotLocalHost();

  /**
   * Rewards and withdrawals processing system for non custodial staking
   * 1. Deploy Dao payment splitter feeSplitter
   * 2. Deploy Withdrawals processing contract
   * 3. Deploy withdrawal pubkey - RewardsReceiver - receives and routes all rewards and exits
   * 4. Set the  RewardsReceiver as setWithdrawalCredential  on sgETH minter - SharedDepositMinter
   */

  // update dao fee splitter addresses
  params = genParams(dh, params);
  console.log("Fee splitter distro: ", params.daoFeeSplitterDistro);

  // Setup the non-custodial staking pipeline incl 1,2,3
  params = await oa.deployNonCustodialStakingPipeline(params);

  await dh.waitIfNotLocalHost();

  /**
   * Servicing for v1
   * 1. Deploy ETH Withdrawals processing contract for v1 veth2
   * 2. Deploy veth2 to sgETH rollover contract for v1
   */
  // await dh.deployContract("WithdrawalsvETH2", "Withdrawals", [params.vETH2Addr, params.rolloverVirtual]);
  await dh.deployContract("WithdrawalQueue", "WithdrawalQueue", [params.minter, params.wsgETH]);

  await dh.deployContract("Rollover", "Rollover", [params.vETH2Addr, sgETHAddrs, params.rolloverVirtual]);

  await dh.waitIfNotLocalHost();

  // // Transfer ownership of any owned components to the multisig
  // await oa.transferRewardsRecvrToMultisig(params);
  // await dh.waitIfNotLocalHost();

  // await oa.transferSgETHToMultisig(params);
  // await dh.waitIfNotLocalHost();

  // // test deposit withdraw flow
  // // await oa.e2e(params);

  // await dh.waitIfNotLocalHost();

  await dh.postRun();

  // put the txs after so contracts can be verified properly
  // run the followup script if any of these txs fail
  await dh.waitIfNotLocalHost();

  await addMinter(dh, params);
  // Set the withdrawal contract now that we have it - i.e the rewards recvr
  await setWC(dh, params);

  await oa.transferRewardsRecvrToMultisig(params);
  await dh.waitIfNotLocalHost();

  await oa.transferSgETHToMultisig(params);
  await dh.waitIfNotLocalHost();

  // test deposit withdraw flow
  await oa.e2e(params);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
