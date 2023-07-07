class OA {
  constructor(dh) {
    this.dh = dh;
  }

  async deposit(params = {
    names: {
      minter: 'SharedDepositMinterV2'
    }
  }, amt) {
    let dh = this.dh;
    let c = params.names.minter;
    await dh.getContract(c).deposit({ value: amt });
  };

  async withdraw(params = {
    names: {
      minter: 'SharedDepositMinterV2'
    }
  }, amt) {
    let dh = this.dh;
    let c = params.names.minter;
    await dh.getContract(c).withdraw(amt);
  };

  async depositAndStake(params = {
    names: {
      minter: 'SharedDepositMinterV2'
    }
  }, amt) {
    let dh = this.dh;
    let c = params.names.minter;
    await dh.getContract(c).depositAndStake({ value: amt });
  };

  async unstakeAndWithdraw(params = {
    names: {
      minter: 'SharedDepositMinterV2'
    },
    wsgETH: 'addr'
  }, amt) {
    let dh = this.dh;
    let c = params.names.minter;
    let wsgeth = await dh.getContractAt(params.names.wsgETH, params.wsgETH);
    await wsgeth.approve(dh.addressOf(c), amt);
    await dh.getContract(c).unstakeAndWithdraw(amt, dh.address);
  };

  async getWSGEthBal(params) {
    let wsgeth = await this.dh.getContractAt(params.names.wsgETH, params.wsgETH);
    let bal = await wsgeth.balanceOf(this.dh.address);
    return bal;
  }

  async getSGEthBal(params) {
    let sgeth = await this.dh.getContractAt("SgETH", params.sgETH);
    let bal = await sgeth.balanceOf(this.dh.address);
    return bal;
  }

  async e2e(params = {
    names: {
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
    await new Promise(resolve => setTimeout(resolve, 10000)); // avoid upstream timeouts / rate limits

    recv = await this.getWSGEthBal(params);
    console.log("starting wsgeth bal", recv.toString() / 1e18);
    await this.depositAndStake(params, amt);
    recv = await this.getWSGEthBal(params);
    console.log("Staked Eth, got wsgETH:", amt / 1e18, recv.toString() / 1e18);
    await this.unstakeAndWithdraw(params, amt / 2); // leave  abit int the wsgeth
    recv = await this.getWSGEthBal(params);
    console.log("Unstaked wsgETH, new wsgETH bal:", recv.toString() / 1e18);
    console.log("warmed up stake/unstake");
  }

  async deployWithdrawalsCredentialPipeline(params = {
    sgETH: 'addr',
    daoFeeSplitterDistro: {
      addresses: [],
      values: []
    },
    names: {
      yd: '',
      rewardsReceiver: '',
      withdrawals: '',
      daoFeeSplitter: ''
    }
  }) {
    let dh = this.dh;
    await dh.deployContract(params.names.daoFeeSplitter, params.names.daoFeeSplitter, [
      params.daoFeeSplitterDistro.addresses,
      params.daoFeeSplitterDistro.values,
    ]);
    let feeSplitter = await dh.addressOf(params.names.daoFeeSplitter);
    params.daoFeeSplitter = feeSplitter;

    await dh.deployContract("Withdrawals", "Withdrawals", [params.sgETH, params.sgETHVirtualPrice]);
    let withdrawals = dh.addressOf("Withdrawals");

    await dh.deployContract("YieldDirector", "YieldDirector", [params.sgETH, params.wsgETH, feeSplitter, params.minter]);
    let yd = dh.addressOf("YieldDirector");
    params.yd = yd;

    await dh.deployContract("RewardsReceiver", "RewardsReceiver", [yd, withdrawals]);
    let rewardsReceiver = dh.addressOf("RewardsReceiver");
    params.rewardsReceiver = rewardsReceiver;
    return params;
  }

  async seedRewards(params, amt) {
    let dh = this.dh;
    amt = this.dh.parseEther(amt);
    let rr = await dh.getContractAt(params.names.rewardsReceiver, params.rewardsReceiver)
    let yd = await dh.getContractAt(params.names.yd, params.yd)
    let daoFeeSplitter = await dh.getContractAt(params.names.daoFeeSplitter, params.daoFeeSplitter)
    // await this.dh.deployer.sendTransaction({
    //   to: params.rewardsReceiver,
    //   value: amt
    // })
    await rr.work({value: amt});
    await yd.work();

    // https://github.com/ethers-io/ethers.js/discussions/2345
    // need to spec full fn sig since OZ contract has 2 release fns
    let fnSig = 'release(address,address)';
    await daoFeeSplitter[fnSig](params.sgETH, params.wsgETH)
    console.log("seeded rewards")
  }
}

module.exports = OA;
