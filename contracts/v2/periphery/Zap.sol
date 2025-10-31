// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

import {IERC20MintableBurnable} from "../../interfaces/IERC20MintableBurnable.sol";
import {IWSGEth} from "../../interfaces/IWSGEth.sol";
import {ISharedDeposit} from "../../interfaces/ISharedDeposit.sol";

contract Zap {
    IERC20MintableBurnable public sgeth;
    IWSGEth public wsgeth;
    ISharedDeposit public minter; // solhint-disable-line var-name-mixedcase

    constructor(IERC20MintableBurnable _sgETHAddr, IWSGEth _wsgETHAddr, ISharedDeposit _minter) {
        sgeth = _sgETHAddr;
        wsgeth = _wsgETHAddr;
        minter = _minter;
        uint256 maxInt = 2 ** 256 - 1; // solhint-disable-line var-name-mixedcase

        sgeth.approve(address(_wsgETHAddr), maxInt);
        sgeth.approve(address(_minter), maxInt);
    }

    function depositAndStake() external payable {
        uint256 amt = msg.value;
        minter.deposit{value: amt}();
        wsgeth.deposit(amt, msg.sender);
    }

    function unstakeAndWithdraw(uint256 amount) external {
        uint256 assets = wsgeth.redeem(amount, address(this), msg.sender);
        minter.withdraw(assets, msg.sender);
    }
}
