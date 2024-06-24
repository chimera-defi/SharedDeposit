// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("../lib/DeployHelper.js");
let OA = require("./lib/onchain_actions.js");
let genParams = require("./lib/opts.js");
require("dotenv").config();

async function main() {
  deployer = new ethers.Wallet(network.name == "goerli" ? process.env.GOERLIPK : process.env.LOCALPK, ethers.provider);

  let dh = new DeployHelper(network.name, deployer.address);
  await dh.init(deployer.address, deployer);

  let oa = new OA(dh);
  let params = genParams(dh);

  // let amt = dh.parseEther("0.0042069");
  let amt = oa.calcSeedRewardAmt(params);

  await oa.seedRewards(params, amt);

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
