// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract WithdrawQueue is AccessControl, Pausable, ReentrancyGuard {
    using Address for address payable;

    struct Queue {
        address to;
        uint256 amount;
    }

    uint256 public constant CHUNK_SIZE = 32 ether;

    uint256 front;
    uint256 end;
    uint256 lockedFront;
    uint256 lockedAmount;

    mapping(uint256 => Queue) public queue;

    error NoAvailableQueue();

    constructor() {
        grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function push(address to) external payable nonReentrant {
        Queue memory newWithdraw = Queue({to: to, amount: msg.value});

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
            payable(queue[i].to).sendValue(queue[i].amount);

            unchecked {
                ++i;
            }
        }
    }
}
