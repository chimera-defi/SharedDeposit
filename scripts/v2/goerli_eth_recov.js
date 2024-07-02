// export GOERLIPK='private key';
// npx hardhat run --network goerli --verbose deploy/deploy_minterv2.js
let {DeployHelper} = require("../deploy_utils.js");
let genParams = require("./lib/opts.js");
require("dotenv").config();

async function main() {
  deployer = new ethers.Wallet(network.name == "goerli" ? process.env.GOERLIPK : process.env.LOCALPK, ethers.provider);

  let dh = new DeployHelper(network.name, deployer.address);
  await dh.init(deployer.address, deployer);
  let params = genParams(dh);

  let name = "GoerliETHRecov";

  async function test() {
    let amt = dh.parseEther("0.042069");
    // let who = 'sharedstake.eth'
    let who = "0xa1feaF41d843d53d0F6bEd86a8cF592cE21C409e";
    let ger = await dh.getContract(name);

    let bal = await dh.hre.ethers.provider.getBalance(who);
    console.log(`Bal 1: ${bal.toString()}`);

    await ger.donate(0, {value: amt});

    bal2 = await dh.hre.ethers.provider.getBalance(who);
    console.log(`Bal 2: ${bal.toString()}`);
    console.log(`Bal diff: ${bal.sub(bal2).toString()}`);
  }

  await dh.deployContract(name, name);
  await test();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
