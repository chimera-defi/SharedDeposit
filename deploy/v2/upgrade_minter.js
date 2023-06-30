// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("../deploy_utils.js");
require("dotenv").config();

async function main() {
  deployer = new ethers.Wallet(network.name == "goerli" ? process.env.GOERLIPK : process.env.LOCALPK, ethers.provider);

  let address = deployer.address;
  let dh = new DeployHelper(network.name, address);
  await dh.init(address, deployer);

  let withdrawalCredsPrefix = `0x010000000000000000000000`;

  let params = {
    epochLen: 24 * 60 * 60, // 1 day
    numValidators: 10000,
    adminFee: 0,
    multisigAddr: address, // todo: mainnet fix,
    vETH2Addr: "0x0d3c0916b0df1ae387eda7fd1cb77d2e244826e6",
    sgETHVirtualPrice: "1000000000000000000",
    deployer: address,
    sgETH: "0x453B459249F82ba3f369651aD485Fa11C6F082F8",
    wsgETH: "0xbFA813C3266Af70A5Ddc15d9253655281e2bCd23",
    rewardsReceiver: "0xC9F2ddBf105ff67c2BA30b2dB968Bc564a16ca67",
    rolloverVirtual: "1100000000000000000",
    feeCalcAddr: dh.addressOf(0), // 0x00 address since initial fees = 0
  };

  // do a cycle check to make sure things work right
  // we call the fns twice as warmed up slots change gas costs and this helps set a benchmark
  let m2name = "SharedDepositMinterV2";
  let deposit = async (c = m2name, amt) => {
    await dh.getContract(c).deposit({value: amt / 2});
    await dh.getContract(c).deposit({value: amt / 2});
  };
  let withdraw = async (c = m2name, amt) => {
    await dh.getContract(c).withdraw(amt / 2);
    await dh.getContract(c).withdraw(amt / 2);
  };
  let depositAndStake = async (c = m2name, amt) => {
    await dh.getContract(c).depositAndStake({value: amt / 2});
    await dh.getContract(c).depositAndStake({value: amt / 2});
  };
  let unstakeAndWithdraw = async (c = m2name, amt) => {
    let wsgeth = await dh.getContractAt("WSGETH", params.wsgETH);
    await wsgeth.approve(dh.addressOf(c), amt);
    await dh.getContract(c).unstakeAndWithdraw(amt / 2);
    await dh.getContract(c).unstakeAndWithdraw(amt / 2);
  };

  let setupMinter = async (sgEth) => {
    console.log("minters count: ", await sgEth.getRoleMemberCount(await sgEth.MINTER()));
    let se = await dh.getContractAt("SgETH", params.sgETH);
    se = await se.connect(deployer);
    console.log("se debug", await se.owner());
    
    await se.addMinter(dh.addressOf(m2name));
    console.log("added new minter")

    let eth1Withdraw = `${withdrawalCredsPrefix}${params.rewardsReceiver.split("x")[1]}`;
    await dh.getContract(m2name).setWithdrawalCredential(eth1Withdraw);
    dh.log(" Set Withdawaral credetentials to ", eth1Withdraw);
  };


  await dh.deployContract("SharedDepositMinterV2", "SharedDepositMinterV2", [
    params.numValidators,
    params.adminFee,
    params.feeCalcAddr,
    params.sgETH,
    params.wsgETH,
  ]);

  console.log("Deployed v2", address, deployer.address);

  let sgEth = await dh.getContractAt("SgETH", params.sgETH);
  console.log('sgeth', await sgEth.MINTER(), await sgEth.owner());

  await setupMinter(sgEth);

  console.log("Add miinter to sgETH at", dh.addressOf("SharedDepositMinterV2"), sgEth.address);
  console.log("minters count: ", await sgEth.getRoleMemberCount(await sgEth.MINTER()));
  await deposit(m2name, 1e12);
  await withdraw(m2name, 1e12);
  console.log('warmed up deposit/withdraw');

  await depositAndStake(m2name, 1e12);
  console.log('1')
  await unstakeAndWithdraw(m2name, 1e12);

  // Todo test stake

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
