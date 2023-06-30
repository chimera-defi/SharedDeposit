// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("./deploy_utils.js");
require("dotenv").config();

async function main() {
  deployer = new ethers.Wallet(network.name == "goerli" ? process.env.GOERLIPK : process.env.LOCALPK, ethers.provider);
  // deployer = new ethers.Wallet(process.env.LOCALPK, ethers.provider);

  let address = deployer.address;
  let dh = new DeployHelper(network.name, address);
  await dh.init(address);

  let withdrawalCredsPrefix = `0x010000000000000000000000`;

  let isUpdate = true;

  let params = {
    epochLen: 24 * 60 * 60, // 1 day
    numValidators: 10000,
    adminFee: 0,
    multisigAddr: address, // todo: mainnet fix,
    vETH2Addr: "0x0d3c0916b0df1ae387eda7fd1cb77d2e244826e6",
    sgETHVirtualPrice: "1000000000000000000",
    deployer: address,
    rolloverVirtual: "1100000000000000000",
    feeCalcAddr: dh.addressOf(0), // 0x00 address since initial fees = 0
  };

  let daoFeeSplitterDistro = {
    founder: 1,
    nor: 5,
    dao: 3,
    reflection: 91,
  };
  let prctGlobalToPartOfPrctLocal = (argsObj, partOf) => {
    // call with daoFeeSplitterDistro and partOf = what perct the splitter gets. e.g. 40 if it gets 40%
    // converts daoFeeSplitterDistro as a part of 100% of fees
    // to args for the splitter as part of fees
    // 6% of 100% is (6 * 5) or 30% or (6 * 100 / part) of 20%
    // $6 = (100 * 0.3 * 0.2)
    let scalingFactor = (100 / partOf) * 10; // 300 if partof is 20
    argsObj = {
      operator: (argsObj.founder + argsObj.nor) * scalingFactor,
      daoPay: argsObj.dao * scalingFactor,
      reflectionPay: argsObj.reflection * scalingFactor,
    };
    console.log(argsObj);
    return [argsObj.operator, argsObj.daoPay, argsObj.reflectionPay];
  };

  // do a cycle check to make sure things work right
  // we call the fns twice as warmed up slots change gas costs and this helps set a benchmark
  let m2name = "SharedDepositMinterV2";
  let warmUpDeposit = async (c = m2name, amt) => {
    await dh.getContract(c).deposit({value: amt / 2});
    await dh.getContract(c).deposit({value: amt / 2});
  };
  let warmupWithdraw = async (c = m2name, amt) => {
    await dh.getContract(c).withdraw(amt / 2);
    await dh.getContract(c).withdraw(amt / 2);
  };

  let warmUpDepositWithdraw = async amt => {
    await warmUpDeposit(amt);
    await warmupWithdraw(amt);
    console.log("Deposit withdraw test done");
  };

  if (isUpdate) {
    let sgEth = await dh.getContractAt("SgETH", "0x453B459249F82ba3f369651aD485Fa11C6F082F8");

    await dh.deployContract("SharedDepositMinterV2", "SharedDepositMinterV2", [
      params.numValidators,
      params.adminFee,
      sgEth.address,
    ]);

    console.log(await sgEth.MINTER());

    console.log("minters count: ", await sgEth.getRoleMemberCount(await sgEth.MINTER()));
    await sgEth.addMinter(dh.addressOf("SharedDepositMinterV2"));

    console.log("Add miinter to sgETH at", dh.addressOf("SharedDepositMinterV2"), sgEth.address);
    console.log("minters count: ", await sgEth.getRoleMemberCount(await sgEth.MINTER()));
    await warmUpDepositWithdraw(1e12);
    await dh.postRun();
    return;
  }

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

  await dh.deployContract("SharedDepositMinterV2", "SharedDepositMinterV2", [
    params.numValidators,
    params.adminFee,
    params.feeCalcAddr,
    sgETHAddrs,
    wsgETHAddr,
  ]);
  let minter = dh.addressOf("SharedDepositMinterV2");
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
  dh.getContract("SharedDepositMinterV2").setWithdrawalCredential(eth1Withdraw);

  // dh.transact(dh.getContract("SharedDepositMinter").setWithdrawalCredential, eth1Withdraw);
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
  // test deposit withdraw flow

  let amt = 1e16;
  await dh.getContract("SharedDepositMinterV2").deposit({value: amt});
  console.log(" \n Deposited and recv'd SGETH: ", (await dh.getContract("SgETH").balanceOf(address)).toString());
  await dh.getContract("SgETH").approve(wsgETHAddr, amt);
  await dh.getContract("WSGETH").deposit(amt / 2, address);

  console.log("\n Deposited sgETH to wsgETH ");
  await dh.getContract("WSGETH").withdraw(amt / 4, address, address);

  await dh.getContract("SharedDepositMinterV2").withdraw(amt / 2);
  console.log("Deposit withdraw test done");

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
