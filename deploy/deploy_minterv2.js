// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("./deploy_utils.js");
require("dotenv").config();

async function main() {
  deployer = new ethers.Wallet(process.env.GOERLIPK, ethers.provider);
  let address = deployer.address;
  let dh = new DeployHelper(network.name, address);
  await dh.init(address);

  let withdrawalCredsPrefix = `0x010000000000000000000000`;

  let params = {
    epochLen: 1 * 7 * 24 * 69 * 60, // 1 wk
    numValidators: 10000,
    adminFee: 0,
    multisigAddr: address, // todo: mainnet fix,
    vETH2Addr: "0x0d3c0916b0df1ae387eda7fd1cb77d2e244826e6",
    sgETHVirtualPrice: "1000000000000000000",
    deployer: address,
    rolloverVirtual: "1100000000000000000",
  };

  /** Deploy core of v2 system
   * 1. Deploy sgETH
   * 2. Deploy wsgETH
   * 3. Deploy minter for sgETH - SharedDepositMinter
   * 3a. Add minter to sgETH
   */
  await dh.deployContract("SgETH", "SgETH", []);
  let sgETHAddrs = dh.addressOf("SgETH");

  await dh.deployContract("WSGETH", "WSGETH", [sgETHAddrs, params.epochLen]);
  let wsgETHAddr = dh.addressOf("WSGETH");

  await dh.deployContract("SharedDepositMinter", "SharedDepositMinter", [
    params.numValidators,
    params.adminFee,
    sgETHAddrs,
  ]);
  let minter = dh.addressOf("SharedDepositMinter");
  dh.contracts["SgETH"].contract.addMinter(minter);
  console.log("added minter");

  /**
   * Rewards and withdrawals processing system
   * 4. Deploy Dao payment splitter feeSplitter
   * 5. Deploy Withdrawals processing contract
   * 6. Deploy yield restaker - ETH2SgETHYieldRedirector
   * 7. Deploy withdrawal pubkey - RewardsReceiver - recieves and routes all rewards and exits
   * 7a. Set the  RewardsReceiver as setWithdrawalCredential  on sgETH minter - SharedDepositMinter
   */
  // todo add node op and multisig to feesplitter / use custom instead of OZ generic
  await dh.deployContract("PaymentSplitter", "PaymentSplitter", [[params.deployer], ["20"]]);
  // await dh.deployContract("FeeSplitter", "FeeSplitter", []);
  let feeSplitter = dh.addressOf("PaymentSplitter");

  await dh.deployContract("Withdrawals", "Withdrawals", [sgETHAddrs, params.sgETHVirtualPrice]);
  let withdrawals = dh.addressOf("Withdrawals");

  await dh.deployContract("ETH2SgETHYieldRedirector", "ETH2SgETHYieldRedirector", [
    sgETHAddrs,
    wsgETHAddr,
    feeSplitter,
    minter,
  ]);
  let converter = dh.addressOf("ETH2SgETHYieldRedirector");

  await dh.deployContract("RewardsReceiver", "RewardsReceiver", [converter, withdrawals]);
  let rewardsReceiver = dh.addressOf("RewardsReceiver");

  // see https://github.com/ethereum/consensus-specs/pull/2149/files & https://github.com/stakewise/contracts/blob/0e51a35e58676491060df84d665e7ebb0e735d17/test/pool/depositDataMerkleRoot.js#L140
  // pubkey is 0x01 + (11 bytes?) 20 0s + eth1 addr 20 bytes (40 characters)  ? = final length 66
  //
  let eth1Withdraw = `${withdrawalCredsPrefix}${rewardsReceiver.split("x")[1]}`;
  dh.getContract("SharedDepositMinter").setWithdrawalCredential(eth1Withdraw);

  // dh.transact(dh.getContract("SharedDepositMinter").setWithdrawalCredential, rewardsReceiver);
  console.log(`setWithdrawalCredential ${eth1Withdraw}`);
  /**
   * Servicing for v1
   * 8. Deploy ETH Withdrawals processing contract for v1 veth2
   * 9. Deploy veth2 to sgETH rollover contract for v1
   */
  await dh.deployContract("WithdrawalsvETH2", "Withdrawals", [params.vETH2Addr, params.rolloverVirtual]);

  await dh.deployContract("Rollover", "Rollover", [params.vETH2Addr, sgETHAddrs, params.rolloverVirtual]);

  // Todo: ownership transfers
  // transferFeeSplittertoDao();

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
