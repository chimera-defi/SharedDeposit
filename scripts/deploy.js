// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
require('@openzeppelin/hardhat-upgrades');
async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const [deployer] = await ethers.getSigners();
  console.log(
    "Deploying contracts with the account:",
    deployer.address
  );
  console.log("Account balance:", (await deployer.getBalance()).toString());

  const veth2_args = [
    deployer.address,
    deployer.address,
    Date.now() + 500
  ]
  const vEth2 = await hre.ethers.getContractFactory("vEth2");
  const veth2_contract = await vEth2.deploy(...veth2_args)
  const veth2_contract_address = veth2_contract.address
  console.log("vEth2 deployed to:", veth2_contract_address);
  console.log(`With constructor args: ${veth2_args.join(', ')}`)
  await veth2_contract.deployTransaction.wait()
  await veth2_contract.deployed();
  await new Promise(resolve => setTimeout(resolve, 200000))

  const constructorArgs = [
    1000000,
    32,
    true
  ]
  constructorArgs.push(veth2_contract.address)
  const SharedDeposit = await hre.ethers.getContractFactory("SharedDeposit");
  console.log("Deploying SharedDeposit...");
  console.log(`With constructor args: ${constructorArgs.join(', ')}`)

  const sd = await upgrades.deployProxy(SharedDeposit, constructorArgs);
  console.log("SharedDeposit proxy deployed to:", sd.address);
  await sd.deployTransaction.wait()
  await sd.deployed();
  await new Promise(resolve => setTimeout(resolve, 200000))

  // let impl =  await sd.implementation().address;
  // console.log("SharedDeposit deployed to:", impl);
  let cps = await sd.costPerShare();
  console.log(sd);
  debugger;
  console.log("Cost per share", cps)
  await veth2_contract.setMinter(sd.address)


  await hre.run("verify:verify", {
    address: veth2_contract_address,
    constructorArguments: veth2_args
  })
  await hre.run("verify:verify", {
    address: sd.address,
    constructorArguments: constructorArgs,
    network: 'goerli'
  })

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
