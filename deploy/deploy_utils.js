const hre = require("hardhat");
const fs = require("fs");
const {ethers} = hre;

const log = txt => {
  txt = txt + "\n";
  console.log(txt);
  fs.writeFileSync("log.txt", txt, {flag: "a"});
};

const _getOverrides = async () => {
  const overridesForEIP1559 = {
    type: 2,
    maxFeePerGas: ethers.utils.parseUnits("10", "gwei"),
    maxPriorityFeePerGas: ethers.utils.parseUnits("3", "gwei"),
    gasLimit: 8000000,
  };
  const gasPrice = await hre.ethers.provider.getGasPrice();
  overridesForEIP1559.maxFeePerGas = gasPrice * 3;
  // overridesForEIP1559.maxPriorityFeePerGas = gasPrice;
  return overridesForEIP1559;
};

const _verifyBase = async (contract, launchNetwork, cArgs) => {
  try {
    await hre.run("verify:verify", {
      address: contract.address,
      constructorArguments: cArgs,
      network: launchNetwork,
    });
    log(`Verified ${JSON.stringify(contract)} on network: ${launchNetwork} with constructor args ${cArgs.join(", ")}`);
    log("\n");
  } catch (e) {
    log(`Etherscan verification failed w/ ${e} | Args: ${cArgs} | on ${launchNetwork} for ${contract.address}`);
    // log(cArgs, launchNetwork, contract);
  }
};

const _verify = async (contract, launchNetwork, cArgs) => {
  if (!launchNetwork || launchNetwork == "hardhat") return;
  await new Promise(resolve => setTimeout(resolve, 10000));
  await _verifyBase(contract, launchNetwork, cArgs);
};

const _deployContract = async (name, launchNetwork = false, cArgs = []) => {
  const overridesForEIP1559 = await _getOverrides();
  const factory = await hre.ethers.getContractFactory(name);
  const contract = await factory.deploy(...cArgs, overridesForEIP1559);
  await contract.deployTransaction.wait(1);
  await contract.deployed();
  // await _verify(contract, launchNetwork, cArgs);
  log(`\n Deployed ${name} to ${contract.address} on ${launchNetwork}`);
  return Promise.resolve({contract: contract, args: cArgs, initialized: false, srcName: name});
};

function chunkArray(array, size) {
  if (array.length <= size) {
    return [array];
  }
  return [array.slice(0, size), ...chunkArray(array.slice(size), size)];
}

const _verifyAll = async (allContracts, launchNetwork) => {
  log("starting verifyall");
  if (!launchNetwork || launchNetwork == "hardhat") return;
  log("Waiting 10s to make sure everything has propagated on etherscan");
  await new Promise(resolve => setTimeout(resolve, 10000));
  // wait 10s to make sure everything has propagated on etherscan

  let contractArr = [];
  Object.keys(allContracts).forEach(k => {
    let obj = allContracts[k];
    contractArr.push({
      address: obj.contract.address,
      args: obj.args,
      initialized: obj.initialized,
    });
  });

  contractArr = chunkArray(contractArr, 5);

  for (const arr of contractArr) {
    await Promise.all(
      arr.map(async contract => {
        log(`Verifying ${JSON.stringify(contract)} at ${contract.address} `);
        await _verifyBase(contract, launchNetwork, contract.initialized ? [] : contract.args);
      }),
    );
    log("Waiting 2 s for Etherscan API limit of 5 calls/s");
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
  log("\n\n Verifications finished:  \n\n");
};

const _deployInitializableContract = async (name, launchNetwork = false, initArgs = []) => {
  const overridesForEIP1559 = await _getOverrides();
  const {contract, _} = await _deployContract(name, launchNetwork, []);
  if (initArgs.length > 0) await contract.initialize(...initArgs, overridesForEIP1559);
  log(`Initialized ${name} with ${initArgs.toString()} \n`);
  return Promise.resolve({contract: contract, args: initArgs, initialized: true, srcName: name});
};

const _getAddress = obj => {
  return obj == undefined || obj.contract == undefined
    ? "0x0000000000000000000000000000000000000000"
    : obj.contract.address;
};

const isMainnet = launchNetwork => {
  return launchNetwork == "localhost" || launchNetwork == "mainnet";
};

const _postRun = (contracts, launchNetwork) => {
  log("\n\n Deployment finished. Contracts deployed: \n\n");
  let prefix = "https://";
  if (!isMainnet(launchNetwork)) {
    prefix += `${launchNetwork}.`;
  }
  prefix += "etherscan.io/address/";

  Object.keys(contracts).map(k => {
    let url = prefix + contracts[k].contract.address;
    log(`${k} deployed to ${contracts[k].contract.address} at ${url} `);
  });
  fs.writeFileSync("deploy_log.json", JSON.stringify(contracts), {flag: "a"});
};

class DeployHelper {
  constructor(launchNetwork) {
    this.contracts = {};
    this.launchNetwork = launchNetwork;
  }
  async deployContract(name, args) {
    this.contracts[name] = await _deployContract(name, this.launchNetwork, args);
  }
  async deployInitializableContract(name, args) {
    this.contracts[name] = await _deployInitializableContract(name, this.launchNetwork, args);
  }
  addressOf(name) {
    return _getAddress(this.contracts[name]);
  }
  getContract(name) {
    return this.contracts[name].contract;
  }
  async getOverrides() {
    return await _getOverrides();
  }
  async transact(tx, ...args) {
    let overrides = await this.getOverrides();
    tx(...args, overrides);
  }
  async postRun() {
    await _verifyAll(this.contracts, this.launchNetwork);
    _postRun(this.contracts, this.launchNetwork);
  }
}

module.exports = {
  _deployInitializableContract: _deployInitializableContract,
  _deployContract: _deployContract,
  _getAddress: _getAddress,
  _verify: _verify,
  _verifyAll: _verifyAll,
  _postRun: _postRun,
  _getOverrides: _getOverrides,
  log: log,
  isMainnet: isMainnet,
  DeployHelper: DeployHelper,
};
