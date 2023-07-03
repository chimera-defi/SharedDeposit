

async function deployMinterV2(dh, params = {
  numValidators: 100,
  adminFee: 0,
  feeCalcAddr: '',
  sgETH: '',
  wsgETH: '',
  multisigAddr: '',
  names: {
    minter: 'SharedDepositMinterV2'
  }
}) {
  let name = params.names.minter;

  let args = [
    params.numValidators,
    params.adminFee,
    [params.feeCalcAddr, params.sgETH, params.wsgETH, params.multisigAddr]
  ]

  await dh.deployContract(name, name, args);
  console.log("Minter deployed");
  return params;
}

function makeWithdrawalCred(params = {
  rewardsReceiver: 'addr'
}) {
  // see https://github.com/ethereum/consensus-specs/pull/2149/files & https://github.com/stakewise/contracts/blob/0e51a35e58676491060df84d665e7ebb0e735d17/test/pool/depositDataMerkleRoot.js#L140
  // pubkey is 0x01 + (11 bytes?) 20 0s + eth1 addr 20 bytes (40 characters)  ? = final length 66
  //
  let withdrawalCredsPrefix = `0x010000000000000000000000`;
  eth1Withdraw = `${withdrawalCredsPrefix}${params.rewardsReceiver.split("x")[1]}`;
  console.log(`setWithdrawalCredential ${eth1Withdraw}`);

  return eth1Withdraw;
}

async function setWC(dh, params = {
  rewardsReceiver: '0xaddr'
}) {
  let eth1Withdraw = makeWithdrawalCred(params);
  let sc = await dh.getContract(params.names.minter);
  // sc = await sc.connect(dh.deployer);
  await sc.setWithdrawalCredential(eth1Withdraw);
  console.log("Updated withdrawal creds");
}

async function addMinter(dh, params = {
  sgETH: 'addr',
  names: {
    minter: 'SharedDepositMinterV2'
  }
}) {
  let se = await dh.getContractAt("SgETH", params.sgETH);

  let o = await se.owner();
  console.log('add minter fn - ', o, dh.address, dh.deployer.address, params.minter)

  // se = await se.connect(dh.deployer);
  let minter = params.minter ? params.minter : dh.addressOf(params.names.minter);

  await se.addMinter(minter);
  dh.log(`Added new minter at ${minter} to ${params.sgETH}`);
};

module.exports = {
  deployMinterV2: deployMinterV2,
  setWC: setWC,
  addMinter: addMinter
}
