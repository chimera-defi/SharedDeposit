// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
pragma experimental ABIEncoderV2;

import {IERC20MintableBurnable} from "../interfaces/IERC20MintableBurnable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract VaultWithMintableTokenUpgradeable is Initializable {
    event MintableBurnableTokenAddressChanged(address oldAddrs, address newAddrs);

    /* ========== STATE VARIABLES ========== */
    address public TokenAddress;
    IERC20MintableBurnable internal MintableBurnableToken;

    function __VaultWithMintableTokenUpgradeable_init(
        address tokenAddress
    ) internal initializer {
        __VaultWithMintableTokenUpgradeable_init_unchained(
            tokenAddress
        );
    }
    function __VaultWithMintableTokenUpgradeable_init_unchained(
        address tokenAddress
    ) internal initializer {
        MintableBurnableToken = IERC20MintableBurnable(tokenAddress);
    }

    function _setTokenAddress(address tokenAddress) internal {
        emit MintableBurnableTokenAddressChanged(TokenAddress, tokenAddress);
        TokenAddress = tokenAddress;
        MintableBurnableToken = IERC20MintableBurnable(tokenAddress);
    }

    function _mint(address reciever, uint amount) internal {
        MintableBurnableToken.mint(reciever, amount);
    }

    function _burn(address reciever, uint amount) internal {
        require(
            MintableBurnableToken.balanceOf(reciever) >= amount,
            "VaultWithMintableTokenUpgradeable: Sender balance not enough"
        );
        MintableBurnableToken.burn(reciever, amount);
    }
}
