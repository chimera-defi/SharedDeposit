// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("../deploy_utils.js");
let {deployMinterV2} = require("./lib/deployMinterV2.js");
let {addMinter, deposit, depositAndStake, withdraw, unstakeAndWithdraw} = require("./lib/onchain_actions.js");
require("dotenv").config();

async function main() {
  deployer = new ethers.Wallet(network.name == "goerli" ? process.env.GOERLIPK : process.env.LOCALPK, ethers.provider);

  let address = deployer.address;
  let dh = new DeployHelper(network.name, address);
  await dh.init(address, deployer);

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
    minterContractName: "SharedDepositMinterV2",
  };

  await deployMinterV2(dh, params);
  console.log("Minter deployed");

  await addMinter(dh, params);
  console.log("New minter added");

  await deposit(dh, params, 1e12);
  await withdraw(dh, params, 1e12);
  console.log("warmed up deposit/withdraw");

  await depositAndStake(dh, params, 1e12);
  await unstakeAndWithdraw(dh, params, 1e12);
  console.log("warmed up stake/unstake");

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
