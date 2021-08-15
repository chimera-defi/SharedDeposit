// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-deploy");
// const {
//   _verify,
//   _deployInitializableContract,
//   deployVeth2
// } = require('./deploy_v2_utils.js');

module.exports = async ({getNamedAccounts, deployments}) => {
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();
  console.log("Deploying v2");
  console.log(deploy, deployer);

  await main(deploy, deployer)
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
};

module.exports.tags = ["v2"];

async function main() {
  console.log(require("./deploy_v2_utils.js"));
  const {_deployInitializableContract, deployVeth2} = require("./deploy_v2_utils.js");
  console.log(_deployInitializableContract, deployVeth2);
  // deploy, deployer
  const {deployments} = hre; // we get the deployments and getNamedAccounts which are provided by hardhat-deploy.
  const {deploy} = deployments; // The deployments field itself contains the deploy function.
  const [deployer] = await hre.ethers.getSigners();
  // const {deployer} = await getNamedAccounts();

  // console.log("Account balance:", (await deployer.getBalance()).toString());
  const launchNetwork = "goerli";
  // const launchNetwork = false;
  // console.log(launchNetwork, deploy, deployer);

  const contracts = {
    veth2: {},
  };
  let address = deployer.address;

  const veth2Name = "veth2";
  const veth2_args = [address, address, Date.now() + 500];
  contracts[veth2Name] = await deployVeth2(launchNetwork, veth2_args);

  const priceOracleName = "PriceOracle";
  const virtualPrice = BigInt(1026987197948687500).toString();
  contracts[priceOracleName] = await _deployInitializableContract(priceOracleName, launchNetwork, [virtualPrice]);

  const tokenManagerName = "TokenManager";
  contracts[tokenManagerName] = await _deployInitializableContract(tokenManagerName, launchNetwork, [
    contracts[veth2Name].contract.address,
  ]);

  const blocklistName = "Blocklist";
  let blocklist = ["0xf6827E678F2d8F7656E577842a84B602DB202Eec"];
  contracts[blocklistName] = await _deployInitializableContract(blocklistName, launchNetwork, [blocklist]);

  const SharedDepositV2Name = "SharedDepositV2";
  let setupStateArgs = [
    [
      500, // _validatorsCreated
      25, // _performancePercent
      1, // epoch duration in days
      1000, // _numValidators
      100, // _adminFee
      1, // _depositsEnabled
    ],
    [
      "0x00000000219ab540356cBB839Cbe05303d7705Fa", // _depositContractAddress
      contracts[priceOracleName].contract.address,
      contracts[tokenManagerName].contract.address,
      contracts[blocklistName].contract.address,
      "0x0000000000000000000000000000000000000000", // _tokenUtilityModuleAddress
      contracts[veth2Name].contract.address, // _BETHTokenAddress
    ],
  ];
  let constructorArgs = [
    //   1000, // _numValidators
    //   1, // _adminFee
    //   // BigInt(((16000 * 99.685) / 100) * 1e18), //  _currentShares
    //   contracts[veth2Name].contract.address, // _BETHTokenAddress
    //   "0x00000000219ab540356cBB839Cbe05303d7705Fa", // _depositContractAddress
    setupStateArgs[0],
    setupStateArgs[1],
  ];
  contracts[SharedDepositV2Name] = await _deployInitializableContract(
    SharedDepositV2Name,
    launchNetwork,
    constructorArgs,
  );

  // Setup

  // Transfer veth2 control to token manager
  await contracts[veth2Name].contract.setMinter(contracts[tokenManagerName].contract.address);

  // grant the shared deposit v2 a minter role on the token manager
  let minterRole = await contracts[tokenManagerName].contract.MINTER_ROLE();
  await contracts[tokenManagerName].contract.grantRole(minterRole, contracts[SharedDepositV2Name].contract.address);

  return;

  const verify = async (name, cArgs) => {
    if (!launchNetwork) return;
    await new Promise(resolve => setTimeout(resolve, 100000));
    await hre.run("verify:verify", {
      address: contracts[name].address,
      constructorArguments: cArgs,
      network: launchNetwork,
    });
  };

  // for testing we deploy a new veth2
  // const deployVeth2 = async () => {
  //   let address = deployer.address;
  //   const veth2_args = [address, address, Date.now() + 500];
  //   const vEth2 = await hre.ethers.getContractFactory("vEth2");
  //   const veth2_contract = await vEth2.deploy(...veth2_args);
  //   const veth2_contract_address = veth2_contract.address;
  //   console.log("vEth2 deployed to:", veth2_contract_address);
  //   console.log(`With constructor args: ${veth2_args.join(", ")}`);
  //   console.log(veth2_contract);
  //   await veth2_contract.deployTransaction.wait();
  //   await veth2_contract.deployed();
  //   contracts.veth2 = veth2_contract;
  //   contracts.veth2.constructorArgs = veth2_args;
  //   await verify("veth2", veth2_args);
  // };

  // const _deployInitializableContract = async name => {
  //   const factory = await hre.ethers.getContractFactory(name);
  //   const contract = await factory.deploy();
  //   await contract.deployTransaction.wait(1);
  //   await contract.deployed();
  //   contracts[name] = contract;
  //   initializableContracts.push(name);
  //   console.log(`Deployed ${name} to ${contract.address}`);
  //   await verify(name);
  // };

  let cp = fn => {
    console.log(fn.toString());
  };
  let sendeth = async (to, val) => {
    tx = await deployer.sendTransaction({
      to: to,
      value: ethers.utils.parseEther(val.toString()),
    });
    await ethers.provider.send("evm_mine");
  };
  await network.provider.send("evm_increaseTime", [3600]);
  await network.provider.send("evm_mine"); // this one will have 02:00 PM as its timestamp
  now = Date.now() + 1000;

  await ethers.provider.send("evm_setNextBlockTimestamp", [now]);
  await ethers.provider.send("evm_mine");
  let overrides = {
    value: ethers.utils.parseEther("1.0"),
  };
  sd2 = contracts["SharedDepositV2"].contract;
  veth2 = contracts["veth2"].contract;

  sendeth(sd2.address, 105);
  await veth2.mint(deployer.address, BigInt(10e19).toString());

  cp(await veth2.balanceOf(sd2.address));

  await sd2.setupState(
    1,
    contracts.PriceOracle.contract.address,
    contracts.TokenManager.contract.address,
    contracts.Blocklist.contract.address,
  );

  await sd2.toggleDepositsEnabled();
  await sd2.deposit(overrides);
  await veth2.approve(sd2.address, BigInt(100e18));
  await sd2.stakeForWithdraw(BigInt(1e17));
  await sd2.withdrawETHRewardsWithQueue();
  cp(await sd2.getTotalBeneficiaryGains());
  await sd2.getBeneficiaryRewards();

  let week = 6.048e8;
  now = Date.now() + week;

  cp(await ethers.provider.getBalance(sd2.address));

  await ethers.provider.send("evm_setNextBlockTimestamp", [now]);
  await ethers.provider.send("evm_mine");

  // const constructorArgs = [1000, 1, veth2_contract.address];
  constructorArgs.push(veth2_contract.address);
  const SharedDeposit = await hre.ethers.getContractFactory("SharedDeposit");
  console.log(`Deploying SharedDepositV2... using ${deploy}`);
  console.log(`With constructor args: ${constructorArgs.join(", ")}`);

  const sd = await deploy("SharedDeposit", {
    from: deployer.address,
    proxy: true,
    proxyContract: "OptimizedTransparentProxy",
  });

  // await upgrades.deployProxy(SharedDeposit, constructorArgs);
  console.log("SharedDeposit proxy deployed to:", sd.address);
  await sd.deployTransaction.wait();
  await sd.deployed();
  await new Promise(resolve => setTimeout(resolve, 200000));
  await sd.initialize(...constructorArgs);
  console.log("SharedDeposit proxy initialized:", sd.address);

  // let impl =  await sd.implementation().address;
  // console.log("SharedDeposit deployed to:", impl);
  let cps = await sd.costPerShare();
  console.log(sd);
  // debugger;
  console.log("Cost per share", cps);
  await veth2_contract.setMinter(sd.address);

  // We get the contract to deploy
  // const Greeter = await hre.ethers.getContractFactory("Greeter");
  // const greeter = await Greeter.deploy("Hello, Hardhat!");

  // await greeter.deployed();

  // console.log("Greeter deployed to:", greeter.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
