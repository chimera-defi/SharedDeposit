// Need a bridge like impl to allow creating ib-eth backed by staked eth on other chains
// E.g. we will rely on pre-existing bridges
// Expect the user/sender contract to be able to generate weth/eth via anyswap at this contract
// Harvest fn
// Check bal 
//- mint target token via target fn call (do targets need to be configurable?)
// - update virtual price on self
// 
// child contract flow
// - user deposits token
// - token transfered after check via bridge to mainnet
// - user recieves a voucher redeemable after deposit is confirmed for actual tokens
// - 
// secondary oracle 
// trigerred on event from child contract on deposit
// triggers harvest on this root-bridge moving eth into the target
// update virtual price on child contract
// forward costs to user?
// secondary cheap flow? 


pragma solidity 0.8.7;

contract rootBridge is Ownable {

    event SomeEvent(address sender);
    address owner;
    uint256 public virtualPrice; // keep track of a virtual price for upstream
    constructor() {
      owner = msg.sender;
      depositContract = _depositCtrct;
      callData = _callData;
    }

    // Need to allow depositing ether to the contract
    function() public payable {
    }
    
    modifier onlyDAO() {}

    modifier refundGasCost()
    {
        uint remainingGasStart = msg.gas;

        _;

        uint remainingGasEnd = msg.gas;
        uint usedGas = remainingGasStart - remainingGasEnd;
        // Add intrinsic gas and transfer gas. Need to account for gas stipend as well.
        usedGas += 21000 + 9700;
        // Possibly need to check max gasprice and usedGas here to limit possibility for abuse.
        uint gasCost = usedGas * tx.gasprice;
        // Refund gas cost
        tx.origin.transfer(gasCost);
    }

    function doSomething() external refundGasCost {
        SomeEvent(msg.sender);  
    }
    
    function harvest() refundGasCost {
      // keep a bit of eth in reserve - 1m wei
      value = address(this).balance - 2000000;
      // ddeposit bufferedd eth in deposit contract with any needed calls
      address(_depositCtrct).call(abi.encodeWithSelector(this.deposit.selector, value));
      

      // IDepositContract(_depositCtrct).call()
    }
    function unwrap_weth() {}
    
    function exit() {
      // exit via the curve pool? 
    }
}

contract childBridge is Ownable {
  event recievedDeposit();
  uint8 notUpdating;
  uint256[] voucherBatch;
  uint256[] vouchers;
  uint256 tVouchers;
  mapping(uint256 => uint8) voucher2Redemption; // voucher id => [enum - 0-non-redeemable, 1-redeemable, 2-redeemed]
  constructor(address _anyswap, address _rootBridgeAddress, ) {
    anyswap = _anyswap;
    rootBridgeAddress = _rootBridgeAddress;
  }
  modifier notUpdating() {
    require(notUpdating == 1);
  }
  modifier isVoucherRedeemable(uint256 vid) {}
  modifier onlyKeepers() {}
  // cheap option
  function buffer(uint256 amount) {
    IERC20(payToken).transfer(msg.sender, address(this) amount);
    _mintRedeemableVoucher(amount);
  }
  function _mintRedeemableVoucher(uint amount) internal {
    _mint(msg.sender, amount);
    voucherBatch.push(vTokenId);
    tVouchers++;
  }
  function _convertStAssetToAsset() {
  }
  function clearVouchers() {
    for (let i=0; i<voucherBatch.length; i++) {
      uint vbe = voucherBatch[i];
      voucher2Redemption[vbe] = 1;
      vouchers.push(tVouchers);
    }
    delete voucherBatch;
  }
  // expensive option - forward gas costs to user
  function deposit(uint256 amount) {
    IAnyswap(anyswap).deposit(amount, rootBridgeAddress);
  }
  function beginUpddate() onlyKeepers {
    notUpdating = 0;
    deposit(IERC20(payToken).balanceOf(address(this)));
  }
  function endUpdate() onlyKeepers {
    _postDeposit();
  }
  function _postDeposit() internal {
    notUpdating = 1;
    _updateVirtualPrice();
    // mark last batch of vouchers as redeemable
    
  } 
  function redeemVoucher(uint256 vid) isVoucherRedeemable(vid) notUpdating() {}
  function updateVirtualPrice() onlyKeepers {
    _updateVirtualPrice();
  }
  function _updateVirtualPrice internal {}
}



// external keepers
// needs to
// 1. call beginUpddate on child chain e.g. matic on childBridge
// 2. wait for completion of cross chain bridge work 
// 3. call harvest on root chain on rootBridge
// 4. call endUpdaate on childBridge to update virtual price and allow users to redeem their tokens
class KeeperWorker {
  function work1() {
    
  }
}
