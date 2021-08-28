// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const {BigNumber} = require("ethers");
const {ethers} = require("hardhat");
const hre = require("hardhat");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-deploy");
const constants = require("./constants.js");
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
    _verifyAll,
    _postRun,
    _getOverrides,
    log,
    isMainnet,
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
  let initialBalance = await hre.ethers.provider.getBalance(address);
  console.log(`Initial balance of deployer is: ${initialBalance.toString()}`);

  // Token
  let sgtv2 = "SGTv2";
  let maxSupply = constants.maxSupply; // 10 million - 10 000 000
  let sgtv2_args = ["Sharedstake.finance", "SGTv2", maxSupply, address];
  await deployContract(sgtv2, sgtv2_args);
  sgtv2_addr = addressOf(sgtv2);

  const blocklistName = "Blocklist";
  if (isMainnet(launchNetwork)) {
    // contracts[blocklistName] = {
    //   contract: {
    //     address: constants.blocklistAddress,
    //   },
    // };
    await deployInitializableContract(blocklistName, [constants.blocklist]);
  } else {
    contracts[blocklistName] = await _deployInitializableContract(blocklistName, launchNetwork, [
      constants.blocklist.concat(address),
    ]);
  }

  // Vote escrow

  let vef = "VoteEscrowFactory";
  await deployContract(vef);
  const ve = "VoteEscrow";
  let ve_args = ["Vote Escrowed Sharedstake Gov token", "veSGT", sgtv2_addr, "10"];
  // await deployContract(ve, ve_args);
  // let ve_address = await contracts[vef].contract.createVoteEscrowContract(...ve_args);
  // console.log(ve_address);
  // Receive an event when ANY transfer occurs

  let verifyVE = async () => {
    return new Promise(async resolve => {
      contracts[vef].contract.on("VoteEscrowCreated", async (address, name, symbol, event) => {
        console.log(`${address} sent to ${name} ${symbol}`);
        contracts[ve] = {contract: {address: address}};
        // await _verify(contracts[ve], launchNetwork, ve_args);
        resolve();
        // console.log(event);    console.log(event.decode());

        // The event object contains the verbatim log data, the
        // EventFragment and functions to fetch the block,
        // transaction and receipt and event functions
      });
    });
  };
  // await verifyVE();
  //  contracts[vef].contract.on("VoteEscrowCreated", (address, name, symbol, event) => {
  //     console.log(`${ from } sent to ${ to}`);
  //     await _verify()
  //     // console.log(event);    console.log(event.decode());

  //     // The event object contains the verbatim log data, the
  //     // EventFragment and functions to fetch the block,
  //     // transaction and receipt and event functions
  // });

  // Vesting
  let founderVesting = "founderVesting";
  let treasuryVesting = "treasuryVesting";
  let startTime = (await hre.ethers.provider.getBlock()).timestamp + 60;

  let founder_benefactor_address, multisig_address;
  if (!isMainnet(launchNetwork)) {
    founder_benefactor_address = address;
    multisig_address = address;
  } else {
    founder_benefactor_address = constants.benefactor;
    multisig_address = constants.multisig_address;
  }
  let vesting = "SimpleVesting";

  let founder_vesting_args = [
    sgtv2_addr, //
    founder_benefactor_address, // beneficiary
    founder_benefactor_address, // gov
    startTime,
    0, // cliff
    constants.twoYearsInSeconds,
  ];
  contracts[founderVesting] = await _deployContract(vesting, launchNetwork, founder_vesting_args);

  let treasury_vesting_args = [
    sgtv2_addr,
    multisig_address,
    multisig_address,
    startTime,
    0,
    constants.twoYearsInSeconds,
  ];
  contracts[treasuryVesting] = await _deployContract(vesting, launchNetwork, treasury_vesting_args);

  // Farmning
  let fund = "FundDistributor";
  let fund_args = [sgtv2_addr];
  await deployInitializableContract(fund, fund_args);

  let masterChef = "MasterChef";
  let mc_args = [sgtv2_addr, addressOf(fund), addressOf()];
  await deployContract(masterChef, mc_args);

  if (!isMainnet(launchNetwork)) {
    let sgtv1_args = ["Sharedstake.finance", "SGTv1", maxSupply, address];
    contracts["SGTv1"] = await _deployContract("SGTv2", launchNetwork, sgtv1_args);
  } else {
    contracts["SGTv1"] = {
      contract: {
        address: constants.oldSgt,
      },
    };
  }

  console.log("here", addressOf(), contracts["SGTv1"].contract.address, sgtv2_addr, addressOf(blocklistName));

  let tokenMigrator = "TokenMigrator";
  let tmargs = [contracts["SGTv1"].contract.address, sgtv2_addr, addressOf(blocklistName)];
  await deployContract(tokenMigrator, tmargs);

  let overrides = await _getOverrides();
  if (!isMainnet(launchNetwork)) {
    let faucet = "Faucet";
    let faucet_args = [sgtv2_addr, ethers.utils.parseEther((10 ** 3).toString())];
    await deployContract(faucet, faucet_args);
    // await contracts[sgtv2].contract.transfer(addressOf(faucet), maxSupply.div(2).toString());

    contracts["FaucetOldToken"] = await _deployContract(faucet, launchNetwork, [
      contracts["SGTv1"].contract.address,
      ethers.utils.parseEther((10 ** 3).toString()),
    ]);
    await contracts[sgtv2].contract.transfer(
      addressOf(faucet),
      ethers.utils.parseEther((1 * 10 ** 6).toString()),
      overrides,
    );

    await contracts["SGTv1"].contract.transfer(addressOf("FaucetOldToken"), maxSupply.div(2).toString(), overrides);
  }

  await contracts[sgtv2].contract.transfer(addressOf(tokenMigrator), constants.tokensInMigrator, overrides);
  await contracts[sgtv2].contract.transfer(addressOf(treasuryVesting), constants.tokensInTreasury, overrides);
  await contracts[sgtv2].contract.transfer(addressOf(founderVesting), constants.tokensInFounder, overrides);
  await contracts[sgtv2].contract.transfer(addressOf(fund), constants.tokensInFarmEth, overrides);

  // Add masterchef as requester to funddistributor
  await contracts[fund].contract.addRequester(addressOf(masterChef), overrides);

  let mc = contracts[masterChef].contract;
  // Add new token to farming contract as a pool
  await mc.add(constants.SGTv2AP, addressOf(sgtv2), constants.zeroAddress, overrides);
  if (isMainnet(launchNetwork)) {
    // add veth2
    await mc.add(constants.SGTv2AP, constants.veth2, constants.zeroAddress, overrides);
  }
  await mc.setFund(addressOf(fund), overrides);
  await mc.setRewardPerSecond(constants.rewardsPerSecond, overrides);

  await _verifyAll(contracts, launchNetwork);
  await _postRun(contracts, launchNetwork);

  let finalBalance = await hre.ethers.provider.getBalance(address);
  log(
    `Total cost of deploys: ${(initialBalance - finalBalance).toString()} with gas price: ${JSON.stringify(overrides)}`,
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
