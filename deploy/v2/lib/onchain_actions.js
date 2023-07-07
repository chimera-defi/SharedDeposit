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
    let feeSplitter = dh.addressOf(params.names.daoFeeSplitter);
    params.daoFeeSplitter = feeSplitter;

    await dh.deployContract("Withdrawals", "Withdrawals", [params.sgETH, params.sgETHVirtualPrice]);
    let withdrawals = dh.addressOf("Withdrawals");

    // await dh.deployContract("YieldDirector", "YieldDirector", [params.sgETH, params.wsgETH, params.daoFeeSplitter, params.minter]);
    // let yd = dh.addressOf("YieldDirector");
    // params.yd = yd;

    await dh.deployContract("RewardsReceiver", "RewardsReceiver", [withdrawals,  [params.sgETH, params.wsgETH, params.daoFeeSplitter, params.minter]]);
    let rewardsReceiver = dh.addressOf("RewardsReceiver");
    params.rewardsReceiver = rewardsReceiver;
    return params;
  }

  async calcSeedRewardAmt(params) {
    let total = await getSGEthBal(params.wsgETH)
    // convert total to expected 5% yield
    total = this.dh.parseEther(total.toString())
    total = total.dividedBy(20);
    // convert from 5% apr to daily 
    total = total.dividedBy(365);
    return total;
  }

  async seedRewards(params, amt) {
    let dh = this.dh;
    amt = this.dh.parseEther(amt);
    let rr = await dh.getContractAt(params.names.rewardsReceiver, params.rewardsReceiver)
    let daoFeeSplitter = await dh.getContractAt(params.names.daoFeeSplitter, params.daoFeeSplitter)
    let wsgETH = await dh.getContractAt(params.names.wsgETH, params.wsgETH);
    let pps = await wsgETH.pricePerShare();
    console.log('Initial price per share:', pps.toString() / 1e18)
    // await this.dh.deployer.sendTransaction({
    //   to: params.rewardsReceiver,
    //   value: amt
    // })
    await rr.work({value: amt});
    // await yd.work();

    // https://github.com/ethers-io/ethers.js/discussions/2345
    // need to spec full fn sig since OZ contract has 2 release fns
    let fnSig = 'release(address,address)';
    await daoFeeSplitter[fnSig](params.sgETH, params.wsgETH)
    pps = await wsgETH.pricePerShare();
    console.log("seeded rewards; Amt: ", amt.toString() / 1e18, "Price per share: ", pps.toString() / 1e18)
  }

  async depositEth2(params, validators) {
    let arrayify = this.dh.hre.ethers.utils.arrayify;
    let _make = (validators) => {
      let _pubkeys = [], _sigs = [], _ddrs = [];
      validators.forEach(v => {
        _pubkeys.push(v.pubkey);
        _sigs.push(v.signature);
        _ddrs.push(v.deposit_data_root);
      });
      _pubkeys = arrayify(_pubkeys);
      _sigs = arrayify(_sigs);
      _ddrs = arrayify(_ddrs);
      return {
        pubkeys: _pubkeys,
        sigs: _sigs,
        ddrs: _ddrs
      }
    }

    let args = _make(validators);

    let minter = await dh.getContractAt(params.names.minter, params.minter);
    let bal = this.dh.getBalance(params.minter);

    await minter.batchDepositToEth2(args.pubkeys, args.sigs, args.ddrs)
    let bal2 = this.dh.getBalance(params.minter)

    console.log(`Starting Balance: ${bal.toString() / 1e18} \n Ending Balance: ${bal2.toString()}`)
  }
}

module.exports = OA;
