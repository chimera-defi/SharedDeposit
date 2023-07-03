class OA {
  constructor(dh) {
    this.dh = dh;
  }

  async deposit(params = {  names: {
    minter: 'SharedDepositMinterV2'
  }
  }, amt) {
    let dh = this.dh;
    let c = params.names.minter;
    await dh.getContract(c).deposit({ value: amt / 2 });
    await dh.getContract(c).deposit({ value: amt / 2 });
  };

  async withdraw(params = {  names: {
    minter: 'SharedDepositMinterV2'
  }
  }, amt) {
    let dh = this.dh;
    let c = params.names.minter;
    await dh.getContract(c).withdraw(amt / 2);
    await dh.getContract(c).withdraw(amt / 2);
  };

  async depositAndStake(params = {  names: {
    minter: 'SharedDepositMinterV2'
  }
  }, amt) {
    let dh = this.dh;
    let c = params.names.minter;
    await dh.getContract(c).depositAndStake({ value: amt });
    await dh.getContract(c).depositAndStake({ value: amt / 2 });
  };

  async unstakeAndWithdraw(params = {  names: {
    minter: 'SharedDepositMinterV2'
  },
    wsgETH: 'addr'
  }, amt) {
    let dh = this.dh;
    let c = params.names.minter;
    let wsgeth = await dh.getContractAt("WSGETH", params.wsgETH);
    await wsgeth.approve(dh.addressOf(c), amt);
    await dh.getContract(c).unstakeAndWithdraw(amt / 2, dh.address);
    await dh.getContract(c).unstakeAndWithdraw(amt / 2, dh.address);
  };

  async getWSGEthBal(params) {
    let wsgeth = await this.dh.getContractAt("WSGETH", params.wsgETH);
    let bal = await wsgeth.balanceOf(this.dh.address);
    return bal;
  }

  async getSGEthBal(params) {
    let sgeth = await this.dh.getContractAt("SgETH", params.sgETH);
    let bal = await sgeth.balanceOf(this.dh.address);
    return bal;
  }

  async e2e(params = {  names: {
    minter: 'SharedDepositMinterV2'
  },
    principal: 0
  }) {
    params.wsgETH = params.wsgETH?.length > 0 ? params.wsgETH : this.dh.addressOf(params.names.minter)
    let amt = params.principal > 0 ? params.principal : this.dh.parseEther("0.01");
    let recv;

    recv = await this.getSGEthBal(params);
    console.log("starting sgeth bal", recv.toString() / 1e18);
    await this.deposit(params, amt);
    recv = await this.getSGEthBal(params);
    console.log("Deposited Eth, got sgETH:", amt / 1e18, recv.toString() / 1e18);
    await this.withdraw(params, amt);
    recv = await this.getSGEthBal(params);
    console.log("new sgETH bal post withdraw", recv.toString() / 1e18);
    console.log("warmed up deposit/withdraw");

    recv = await this.getWSGEthBal(params);
    console.log("starting wsgeth bal", recv.toString() / 1e18);
    await this.depositAndStake(params, amt);
    recv = await this.getWSGEthBal(params);
    console.log("Staked Eth, got wsgETH:", amt / 1e18, recv.toString() / 1e18);
    await this.unstakeAndWithdraw(params, amt);
    recv = await this.getWSGEthBal(params);
    console.log("Unstaked wsgETH, new wsgETH bal:", recv.toString() / 1e18);
    console.log("warmed up stake/unstake");
  }
}

module.exports = OA;
