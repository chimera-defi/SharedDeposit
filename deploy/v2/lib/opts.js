
function genParams(dh) {
  let addresses = {
    multisigAddr: dh.address, // todo: mainnet fix, currently deployer addr
    deployer: dh.address,
    feeCalcAddr: dh.addressOf(0), // 0x00 address since initial fees = 0
  };

  let GoerliDeployedAddresses = {
    vETH2Addr: "0x0d3c0916b0df1ae387eda7fd1cb77d2e244826e6",
    sgETH: "0x453B459249F82ba3f369651aD485Fa11C6F082F8",
    wsgETH: "0xbFA813C3266Af70A5Ddc15d9253655281e2bCd23",
    rewardsReceiver: "0xC9F2ddBf105ff67c2BA30b2dB968Bc564a16ca67",
  }

  let params = {
    epochLen: 24 * 60 * 60, // 1 day
    numValidators: 10000,
    adminFee: 0,
    sgETHVirtualPrice: "1000000000000000000",
    rolloverVirtual: "1100000000000000000",
    names: {
      minter: "SharedDepositMinterV2",
      sgETH: "SgETH",
      wsgETH: "WSGETH",
      withdrawals: "Withdrawals",
      rewardsReceiver: "RewardsReceiver",
      daoFeeSplitter: "PaymentSplitter",
      yd: "YieldDirector"
      
    },
    ...addresses,
    ...GoerliDeployedAddresses
  };

  return params;
}

module.exports = genParams;
