// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ERC4626, ERC20} from "solmate/src/mixins/ERC4626.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {SharedDepositMinterV2} from "./SharedDepositMinterV2.sol";

contract WithdrawQueue is AccessControl, Pausable, ReentrancyGuard {
    using Address for address payable;

    struct Queue {
        address to;
        uint256 amount;
        address token;
        uint256 tokenAmount;
    }

    address public immutable sgEth;
    address public immutable wsgEth;
    SharedDepositMinterV2 public immutable minter;

    uint256 public constant CHUNK_SIZE = 32 ether;

    uint256 private front;
    uint256 private end;
    uint256 private lockedFront;
    uint256 private lockedAmount;

    mapping(uint256 => Queue) public queue;

    error NoAvailableQueue();

    constructor(address _sgEth, address _wsgEth, address _minter) {
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        sgEth = _sgEth;
        wsgEth = _wsgEth;
        minter = SharedDepositMinterV2(_minter);
    }

    function push(address to) external payable {
        _push(to, msg.value, address(0), msg.value);
    }

    function pushSgEth(address to, uint256 amount) external {
        ERC20(sgEth).transferFrom(msg.sender, address(this), amount);
        _push(to, amount, sgEth, amount);
    }

    function pushWsgEth(address to, uint256 amount) external {
        ERC20(wsgEth).transferFrom(msg.sender, address(this), amount);

        uint256 redeemable = ERC4626(wsgEth).previewRedeem(amount);
        _push(to, redeemable, wsgEth, amount);
    }

    function _push(address to, uint256 amount, address token, uint256 tokenAmount) internal nonReentrant {
        Queue memory newWithdraw = Queue({to: to, amount: msg.value, token: token, tokenAmount: tokenAmount});

        queue[end] = newWithdraw;
        lockedAmount += msg.value;
        end++;

        if (lockedAmount >= CHUNK_SIZE) {
            lockedAmount = 0;
            lockedFront = end;
        }
    }

    function processWithdraw() external nonReentrant {
        if (lockedFront == front) {
            revert NoAvailableQueue();
        }

        for (uint256 i = front; i < lockedFront; ) {
            if (queue[i].token == sgEth) {
                minter.withdraw(queue[i].tokenAmount);
            } else if (queue[i].token == wsgEth) {
                minter.unstakeAndWithdraw(queue[i].tokenAmount, address(this));
            }

            payable(queue[i].to).sendValue(queue[i].amount);

            unchecked {
                ++i;
            }
        }
    }
}
