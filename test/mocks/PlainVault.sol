// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

contract PlainVault is ERC4626 {
    uint8 private immutable _offset;

    constructor(IERC20 asset_, uint8 offset_) ERC20("Plain", "PLN") ERC4626(asset_) {
        _offset = offset_;
    }

    function _decimalsOffset() internal view override returns (uint8) {
        return _offset;
    }
}
