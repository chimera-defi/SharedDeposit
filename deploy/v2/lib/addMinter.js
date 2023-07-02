
async function addMinter(dh, params = {
  sgETH: 'addr',
  minterContractName: ''
}) {
  let se = await dh.getContractAt("SgETH", params.sgETH);
  se = await se.connect(dh.address);

  await se.addMinter(dh.addressOf(minterContractName));
  console.log("added new minter");
};

module.exports = {
  addMinter: addMinter
}
