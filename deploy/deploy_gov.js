// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-deploy");

module.exports = async ({getNamedAccounts, deployments}) => {
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();
  await main(deploy, deployer)
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
};

async function main() {
  const {_deployInitializableContract, _deployContract, _getAddress} = require("./deploy_utils.js");
  // deploy, deployer
  const [deployer] = await hre.ethers.getSigners();
  let address = deployer.address;
  let launchNetwork = network.name;
  let contracts = {};

  const deployContract = async (name, args) => {
    contracts[name] = await _deployContract(name, launchNetwork, args);
  };
  const deployInitializableContract = async (name, args) => {
    contracts[name] = await _deployInitializableContract(name, launchNetwork, args);
  };

  const addressOf = name => {
    return _getAddress(contracts[name]);
  };

  const sgtv2 = "SGTv2";
  const maxSupply = ethers.utils.parseEther((10 ** 7).toString()); // 10 million - 10 000 000
  const sgtv2_args = ["Sharedstake.finance", "SGTv2", maxSupply, address];
  await deployContract(sgtv2, sgtv2_args);
  sgtv2_addr = addressOf(sgtv2);

  const ve = "VoteEscrow";
  const ve_args = ["Vote Escrowed Sharedstake Gov token", "veSGT", sgtv2_addr, "10"];
  await deployContract(ve, ve_args);

  const faucet = "Faucet";
  const faucet_args = [sgtv2_addr, maxSupply.div(2)];
  await deployContract(faucet, faucet_args);

  await contracts[sgtv2].contract.transfer(sgtv2_addr, maxSupply.div(2).toString());

  // Farmning
  const fund = "FundDistributor";
  const fund_args = [sgtv2_addr];
  await deployInitializableContract(fund, fund_args);

  const masterChef = "MasterChef";
  const mc_args = [sgtv2_addr, addressOf(fund), addressOf()];
  await deployContract(masterChef, mc_args);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
