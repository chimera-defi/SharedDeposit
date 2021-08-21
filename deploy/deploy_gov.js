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
  let {
    _deployInitializableContract,
    _deployContract,
    _getAddress,
    _verify,
    _printesults,
  } = require("./deploy_utils.js");
  // deploy, deployer
  const [deployer] = await hre.ethers.getSigners();
  let address = deployer.address;
  let launchNetwork = network.name;
  let contracts = {};

  let deployContract = async (name, args) => {
    contracts[name] = await _deployContract(name, launchNetwork, args);
  };
  let deployInitializableContract = async (name, args) => {
    contracts[name] = await _deployInitializableContract(name, launchNetwork, args);
  };

  let addressOf = name => {
    return _getAddress(contracts[name]);
  };
  // console.log(Object.keys(contracts), ve, name);
  // Token
  let sgtv2 = "SGTv2";
  let maxSupply = ethers.utils.parseEther((10 ** 7).toString()); // 10 million - 10 000 000
  let sgtv2_args = ["Sharedstake.finance", "SGTv2", maxSupply, address];
  await deployContract(sgtv2, sgtv2_args);
  sgtv2_addr = addressOf(sgtv2);

  // Vote escrow

  let vef = "VoteEscrowFactory";
  await deployContract(vef);
  const ve = "VoteEscrow";
  let ve_args = ["Vote Escrowed Sharedstake Gov token", "veSGT", sgtv2_addr, "10"];
  // await deployContract(ve, ve_args);
  let ve_address = await contracts[vef].contract.createVoteEscrowContract(...ve_args);
  console.log(ve_address);
  // Receive an event when ANY transfer occurs

  let verifyVE = async () => {
    return new Promise(async resolve => {
      contracts[vef].contract.on("VoteEscrowCreated", async (address, name, symbol, event) => {
        console.log(`${address} sent to ${name} ${symbol}`);
        contracts[ve] = {address: address};
        // await _verify(contracts[ve], launchNetwork, ve_args);
        resolve();
        // console.log(event);    console.log(event.decode());

        // The event object contains the verbatim log data, the
        // EventFragment and functions to fetch the block,
        // transaction and receipt and event functions
      });
    });
  };
  await verifyVE();
  //  contracts[vef].contract.on("VoteEscrowCreated", (address, name, symbol, event) => {
  //     console.log(`${ from } sent to ${ to}`);
  //     await _verify()
  //     // console.log(event);    console.log(event.decode());

  //     // The event object contains the verbatim log data, the
  //     // EventFragment and functions to fetch the block,
  //     // transaction and receipt and event functions
  // });

  if (launchNetwork !== "mainnet") {
    let faucet = "Faucet";
    let faucet_args = [sgtv2_addr, maxSupply.div(2)];
    await deployContract(faucet, faucet_args);
    await contracts[sgtv2].contract.transfer(sgtv2_addr, maxSupply.div(2).toString());
  }

  // Vesting
  let founderVesting = "founderVesting";
  let treasuryVesting = "treasuryVesting";
  let startTime = Date.now() + 500; // Add buffer to keep tx from failing
  let twoYears = 2 * 366 * 24 * 60;

  let founder_benefactor_address, multisig_address;
  if (launchNetwork !== "mainnet") {
    founder_benefactor_address = address;
    multisig_address = address;
  } else {
    founder_benefactor_address = "0x610c92c70Eb55dFeAFe8970513D13771Da79f2e0";
    multisig_address = "0xeBc37F4c20C7F8336E81fB3aDf82f6372BEf777E";
  }
  let vesting = "SimpleVesting";

  let founder_vesting_args = [
    sgtv2_addr, //
    founder_benefactor_address, // beneficiary
    founder_benefactor_address, // gov
    startTime,
    0, // cliff
    twoYears,
  ];
  contracts[founderVesting] = await _deployInitializableContract(vesting, launchNetwork, founder_vesting_args);

  let treasury_vesting_args = [sgtv2_addr, multisig_address, multisig_address, startTime, 0, twoYears];
  contracts[treasuryVesting] = await _deployInitializableContract(vesting, launchNetwork, treasury_vesting_args);

  // Farmning
  let fund = "FundDistributor";
  let fund_args = [sgtv2_addr];
  await deployInitializableContract(fund, fund_args);

  let masterChef = "MasterChef";
  let mc_args = [sgtv2_addr, addressOf(fund), addressOf()];
  await deployContract(masterChef, mc_args);

  _printesults(contracts);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
