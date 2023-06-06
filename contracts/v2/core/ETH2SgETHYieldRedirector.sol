// Acts as the deposit contract for the reward receiver during normal functioning
// 100% of recieved ETH from rewards is auto-compounded back into sgETH
// 60% is immutably always transfered to wsgETH for staker rewards
// 40% is transferred to a splitter the DAO can modulate for nor payments and other use cases

// call work() to process eth
pragma solidity 0.8.20;
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PaymentSplitter} from "../../lib/PaymentSplitter.sol";
import {ISharedDeposit} from "../../interfaces/ISharedDeposit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ETH2SgETHYieldRedirector is Ownable2Step, PaymentSplitter {
    address public immutable sgETH;
    address public immutable wsgETH;
    address public immutable feeSplitter;
    address public immutable minter;
    uint256[] public split;
    address[] public splitAddrs;

    constructor(
        address _sgETh,
        address _wsgETH,
        address _splitter,
        address _minter
    ) Ownable2Step() PaymentSplitter(splitAddrs, split) {
        sgETH = _sgETh;
        wsgETH = _wsgETH;
        feeSplitter = _splitter;
        minter = _minter;

        _addPayee(_wsgETH, 60);
        _addPayee(_splitter, 40);
    }

    // Blocks accidentally sending ETH instead of sgETH to the addresses
    function release(address payable account) public override {
        release(IERC20(sgETH), account);
    }

    function work() external {
        // convert eth 2 sgETH
        ISharedDeposit(minter).deposit{value: address(this).balance}();
        release(payable(wsgETH));
        release(payable(feeSplitter));
    }
}
