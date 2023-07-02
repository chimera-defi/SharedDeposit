

function makeWithdrawalCred(params = {
  rewardsReceiver: 'addr'
}) {
  let withdrawalCredsPrefix = `0x010000000000000000000000`;
  eth1Withdraw = `${withdrawalCredsPrefix}${params.rewardsReceiver.split("x")[1]}`;
  return eth1Withdraw;
}

async function deployMinterV2(dh, params = {
  numValidators: 100,
  adminFee: 0,
  feeCalcAddr: '',
  sgETH: '',
  wsgETH: '',
  multisigAddr: '',
  rewardsReceiver: '',
  minterContractName: 'SharedDepositMinterV2'
}) {
  let name = params.minterContractName;

  let args = [
    params.numValidators,
    params.adminFee,
    [params.feeCalcAddr, params.sgETH, params.wsgETH, params.multisigAddr]
  ]

  await dh.deployContract(name, name, args);
  let eth1Withdraw = makeWithdrawalCred(params);
  let sc = await dh.getContract(name);
  sc = await sc.connect(dh.deployer);

  await sc.setWithdrawalCredential(eth1Withdraw);

  await dh.mine();
}

module.exports = {
  deployMinterV2: deployMinterV2
}
