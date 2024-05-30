//SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

interface ISharedDeposit {
    function donate(uint256 shares) external payable;
}

contract GoerliETHRecov is ISharedDeposit {
    constructor() {}

    // Allows recovering ETH from old v1 goerli minter to test v2

    // needed to set this as a minter
    function donate(uint256 shares) external payable {
        uint256 incoming = msg.value;
        address payable recv = payable(0xa1feaF41d843d53d0F6bEd86a8cF592cE21C409e);

        if (incoming > 0) {
            Address.sendValue(recv, incoming);
        }

        uint256 bal = address(this).balance;
        if (bal > 0) {
            Address.sendValue(recv, bal);
        }
    }
}
