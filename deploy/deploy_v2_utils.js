const hre = require("hardhat");

const _verify = async (contract, launchNetwork, cArgs) => {
  if (!launchNetwork) return;
  await new Promise(resolve => setTimeout(resolve, 100000));
  await hre.run("verify:verify", {
    address: contract.address,
    constructorArguments: cArgs,
    network: launchNetwork,
  });
  console.log("\n");
};

const _deployInitializableContract = async (name, launchNetwork = false, initArgs = []) => {
  const factory = await hre.ethers.getContractFactory(name);
  const contract = await factory.deploy();
  await contract.deployTransaction.wait(1);
  await contract.deployed();
  await _verify(contract, launchNetwork, []);
  if (initArgs.length > 0) await contract.initialize(...initArgs);
  console.log(
    `Deployed ${name} to ${
      contract.address
    } and initialized with ${initArgs.toString()} & verified on network: ${launchNetwork}`,
  );

  return Promise.resolve({contract: contract, args: initArgs});
};

// for testing we deploy a new veth2
const deployVeth2 = async (launchNetwork, veth2_args) => {
  const vEth2 = await hre.ethers.getContractFactory("vEth2");
  const veth2_contract = await vEth2.deploy(...veth2_args);
  console.log("vEth2 deployed to:", veth2_contract.address);
  console.log(`With constructor args: ${veth2_args.join(", ")}`);
  await veth2_contract.deployTransaction.wait();
  await veth2_contract.deployed();
  await _verify(veth2_contract, launchNetwork, veth2_args);
  return Promise.resolve({
    contract: veth2_contract,
    args: veth2_args,
  });
};

module.exports = {
  _deployInitializableContract: _deployInitializableContract,
  _verify: _verify,
  deployVeth2: deployVeth2,
};
