
async function addMinter(dh, params = {
  sgETH: 'addr',
  minterContractName: 'SharedDepositMinterV2'
}) {
  let se = await dh.getContractAt("SgETH", params.sgETH);
  se = await se.connect(dh.deployer);

  await se.addMinter(dh.addressOf(params.minterContractName));
  console.log("added new minter");
};

async function deposit(dh, params = {
  minterContractName: 'SharedDepositMinterV2'
}, amt) {
  let c = params.minterContractName;
  await dh.getContract(c).deposit({ value: amt / 2 });
  await dh.getContract(c).deposit({ value: amt / 2 });
};

async function withdraw(dh, params = {
  minterContractName: 'SharedDepositMinterV2'
}, amt) {
  let c = params.minterContractName;
  await dh.getContract(c).withdraw(amt / 2);
  await dh.getContract(c).withdraw(amt / 2);
};

async function depositAndStake(dh, params = {
  minterContractName: 'SharedDepositMinterV2'
}, amt) {
  let c = params.minterContractName;
  await dh.getContract(c).depositAndStake({ value: amt / 2 });
  await dh.getContract(c).depositAndStake({ value: amt / 2 });
};

async function unstakeAndWithdraw(dh, params = {
  minterContractName: 'SharedDepositMinterV2',
  wsgETH: 'addr'
}, amt) {
  let c = params.minterContractName;
  let wsgeth = await dh.getContractAt("WSGETH", params.wsgETH);
  await wsgeth.approve(dh.addressOf(c), amt);
  await dh.getContract(c).unstakeAndWithdraw(amt / 2, dh.address);
  await dh.getContract(c).unstakeAndWithdraw(amt / 2, dh.address);
};

module.exports = {
  addMinter: addMinter,
  deposit: deposit,
  withdraw: withdraw,
  depositAndStake: depositAndStake,
  unstakeAndWithdraw: unstakeAndWithdraw
}
