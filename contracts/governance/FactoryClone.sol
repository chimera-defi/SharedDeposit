// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./voteEscrow.sol";

contract FactoryClone {
    // address immutable tokenImplementation;

    constructor() public {}

    function createToken(
        address impl,
        string calldata name,
        string calldata symbol,
        uint256 initialSupply
    ) external returns (address) {
        // address clone = Clones.clone(impl);
        // VoteEscrow(clone).initialize(name, symbol, initialSupply, msg.sender);
        // return clone;
    }
}
