// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("../lib/DeployHelper.js");
let genParams = require("../lib/opts.js");
let OA = require("../lib/onchain_actions.js");

require("dotenv").config();

async function main() {
  let dh = new DeployHelper(network.name);
  await dh.init();
  let params = genParams(dh.address);
  dh.multisig_address = params.multisigAddr;

  /**
   * Servicing for v2
   * 1. Deploy ETH Withdrawals queue processing contract
   * 2. Swap out old contract on MinterV2
   */
  await dh.deployContract("WithdrawalQueue", "WithdrawalQueue", [params.minter, params.wsgETH]);

  // Todo: swap out old contract on MinterV2/rewardsRecvr to point to this new withdrawal queue instead of the old withdrawal contract
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
