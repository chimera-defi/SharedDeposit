const hre = require("hardhat");
const {ethers} = hre;

const _getOverrides = async () => {
  const overridesForEIP1559 = {
    type: 2,
    maxFeePerGas: ethers.utils.parseUnits("10", "gwei"),
    maxPriorityFeePerGas: ethers.utils.parseUnits("1", "gwei"),
    gasLimit: 8000000,
  };
  const gasPrice = await hre.ethers.provider.getGasPrice();
  overridesForEIP1559.maxFeePerGas = gasPrice;
  overridesForEIP1559.maxPriorityFeePerGas = gasPrice;
  return overridesForEIP1559;
};

const _verify = async (contract, launchNetwork, cArgs) => {
  if (!launchNetwork || launchNetwork == "hardhat") return;
  await new Promise(resolve => setTimeout(resolve, 50000));
  try {
    await hre.run("verify:verify", {
      address: contract.address,
      constructorArguments: cArgs,
      network: launchNetwork,
    });
    console.log("\n");
  } catch (e) {
    console.log("Etherscan verification failed w/ ", e);
  }
};

const _deployContract = async (name, launchNetwork = false, cArgs = []) => {
  const overridesForEIP1559 = await _getOverrides();
  const factory = await hre.ethers.getContractFactory(name);
  const contract = await factory.deploy(...cArgs, overridesForEIP1559);
  await contract.deployTransaction.wait(1);
  await contract.deployed();
  await _verify(contract, launchNetwork, cArgs);
  console.log(
    `Deployed ${name} to ${contract.address} & verified on network: ${launchNetwork} with constructor args ${cArgs.join(
      ", ",
    )}`,
  );
  return Promise.resolve({contract: contract, args: cArgs});
};

const _deployInitializableContract = async (name, launchNetwork = false, initArgs = []) => {
  const overridesForEIP1559 = await _getOverrides();
  const {contract, _} = await _deployContract(name, launchNetwork, []);
  if (initArgs.length > 0) await contract.initialize(...initArgs, overridesForEIP1559);
  console.log(`Initialized ${name} with ${initArgs.toString()}`);
  return Promise.resolve({contract: contract, args: initArgs});
};

const _getAddress = obj => {
  return obj == undefined || obj.contract == undefined
    ? "0x0000000000000000000000000000000000000000"
    : obj.contract.address;
};

module.exports = {
  _deployInitializableContract: _deployInitializableContract,
  _deployContract: _deployContract,
  _getAddress: _getAddress,
};
