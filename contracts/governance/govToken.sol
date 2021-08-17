pragma solidity 0.8.7;
pragma experimental ABIEncoderV2;
// node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol
// node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol

import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

// import {ERC20CappedUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20CappedUpgradeable.sol";

contract SGTv2 is ERC20VotesUpgradeable {
    /// @notice Address which may mint new tokens
    address public minter;

    /// @notice Minimum time between mints
    // Flash mint protection
    // uint32 public constant minimumTimeBetweenMints;

    function initialize(address minter_) external initializer {
        // __ERC20Capped_init_unchained(100000);
        __ERC20Votes_init_unchained();
        __ERC20Permit_init("SharedStake");
        __ERC20_init_unchained("SharedStake Governance Token v2", "SGTv2");
        minter = minter_;
    }

    /**
     * @notice Change the minter address
     * @param minter_ The address of the new minter
     */
    function setMinter(address minter_) external {
        require(msg.sender == minter, "vETH2::setMinter: only the minter can change the minter address");
        // emit MinterChanged(minter, minter_);
        minter = minter_;
    }

    /**
     * @notice Mint new tokens
     * @param dst The address of the destination account
     * @param rawAmount The number of tokens to be minted
    //  */
    // function mint(address dst, uint256 rawAmount) external {
    //     require(msg.sender == minter, "vETH2::mint: only the minter can mint");
    //     require(block.timestamp >= mintingAllowedAfter, "vETH2::mint: minting not allowed yet");
    //     require(dst != address(0), "vETH2::mint: cannot transfer to the zero address");

    //     // record the mint
    //     mintingAllowedAfter = SafeMath.add(block.timestamp, minimumTimeBetweenMints);

    //     // mint the amount
    //     uint96 amount = safe96(rawAmount, "vETH2::mint: amount exceeds 96 bits");
    //     totalSupply = safe96(SafeMath.add(totalSupply, amount), "vETH2::mint: totalSupply exceeds 96 bits");

    //     // transfer the amount to the recipient
    //     balances[dst] = add96(balances[dst], amount, "vETH2::mint: transfer amount overflows");
    //     emit Transfer(address(0), dst, amount);

    //     // move delegates
    //     _moveDelegates(address(0), delegates[dst], amount);
    // }
}
