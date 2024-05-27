const {ethers} = require("hardhat");
const {expect} = require("chai");

describe("SgETH.sol", () => {
  let sgEth, deployer, alice;
  let MINTER_ROLE;

  beforeEach(async () => {
    const [owner, addr1] = await ethers.getSigners();

    const SgETH = await ethers.getContractFactory("SgETH");
    sgEth = await SgETH.deploy([]);
    await sgEth.deployed();

    deployer = owner;
    alice = addr1;

    MINTER_ROLE = await sgEth.MINTER();
  });

  it("addMinter", async () => {
    await expect(sgEth.connect(alice).addMinter(alice.address)).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${ethers.constants.HashZero}`,
    );
    await expect(sgEth.connect(deployer).addMinter(ethers.constants.AddressZero)).to.be.revertedWith(
      "Zero address detected",
    );

    await expect(sgEth.connect(deployer).addMinter(alice.address))
      .to.be.emit(sgEth, "RoleGranted")
      .withArgs(MINTER_ROLE, alice.address, deployer.address);
  });

  it("removeMinter", async () => {
    await sgEth.connect(deployer).addMinter(alice.address);
    await expect(sgEth.connect(alice).removeMinter(alice.address)).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${ethers.constants.HashZero}`,
    );

    await expect(sgEth.connect(deployer).removeMinter(alice.address))
      .to.be.emit(sgEth, "RoleRevoked")
      .withArgs(MINTER_ROLE, alice.address, deployer.address);
  });

  it("transferOwnership", async () => {
    await expect(sgEth.connect(alice).transferOwnership(alice.address)).to.be.revertedWith(
      `AccessControl: account ${alice.address.toLowerCase()} is missing role ${ethers.constants.HashZero}`,
    );

    await expect(sgEth.connect(deployer).transferOwnership(alice.address))
      .to.be.emit(sgEth, "RoleGranted")
      .withArgs(ethers.constants.HashZero, alice.address, deployer.address)
      .and.to.be.emit(sgEth, "RoleRevoked")
      .withArgs(ethers.constants.HashZero, deployer.address, deployer.address);
  });
});
