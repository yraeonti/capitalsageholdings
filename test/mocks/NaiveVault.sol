// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @dev Pre-v4.9 share math with no virtual shares. Test reference only.
contract NaiveVault is ERC4626 {
    using Math for uint256;

    constructor(IERC20 asset_) ERC20("Naive", "NAV") ERC4626(asset_) {}

    function _convertToShares(uint256 assets, Math.Rounding r) internal view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? assets : assets.mulDiv(supply, totalAssets(), r);
    }

    function _convertToAssets(uint256 shares, Math.Rounding r) internal view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : shares.mulDiv(totalAssets(), supply, r);
    }
}
