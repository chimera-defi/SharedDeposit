// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

// Inherit permit to allow a permit signed approval for gas savings
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
// Token needs to be burnable to allow the voteEscrow to burn self tokens as early withdraw penalyu
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract SGTv2 is ERC20Burnable, ERC20Permit, Ownable {
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address owner
    ) ERC20(name, symbol) ERC20Permit(name) {
        _mint(owner, initialSupply);
    }

    // collect any tokens sent by mistake
    function collect(address _token) external {
        if (_token == address(0)) {
            // token address(0) = ETH
            Address.sendValue(payable(owner()), address(this).balance);
        } else {
            uint256 balance = IERC20(_token).balanceOf(address(this));
            IERC20(_token).transfer(owner(), balance);
        }
    }
}
