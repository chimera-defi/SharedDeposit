// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");
require("@openzeppelin/hardhat-upgrades");
require("hardhat-deploy");

module.exports = async ({ getNamedAccounts, deployments }) => {

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    await main(deploy, deployer)
        .then(() => process.exit(0))
        .catch(error => {
            console.error(error);
            process.exit(1);
        });
};

async function main() {
    const { _deployInitializableContract, _deployContract } = require("./deploy_utils.js");
    // deploy, deployer
    const [deployer] = await hre.ethers.getSigners();
    let address = deployer.address;
    let launchNetwork = network.name;
    let contracts = {};

    const sgtv2 = "SGTv2";
    const maxSupply = ethers.utils.parseEther((10 ** 7).toString()) // 10 million - 10 000 000
    const sgtv2_args = ["Sharedstake.finance", "SGTv2", maxSupply, address];
    contracts[sgtv2] = await _deployContract(sgtv2, launchNetwork, sgtv2_args);

    const ve = "VoteEscrow";
    const ve_args = ["Vote Escrowed Sharedstake Gov token", "veSGT", contracts[sgtv2].contract.address, "10"];
    contracts[ve] = await _deployContract(ve, launchNetwork, ve_args);

    const faucet = "Faucet";
    const faucet_args = [contracts[sgtv2].contract.address, maxSupply.div(2)];
    contracts[faucet] = await _deployContract(faucet, launchNetwork, faucet_args);

    await contracts[sgtv2].contract.transfer(contracts[faucet].contract.address, maxSupply.div(2).toString());
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
