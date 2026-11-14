// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC4626Test} from "erc4626-tests/ERC4626.test.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {VaultDeployer} from "./utils/VaultDeployer.sol";

contract ERC4626ComplianceTest is ERC4626Test, VaultDeployer {
    function setUp() public override {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        _underlying_ = address(asset);
        _vault_ = address(_deployVault(asset, 100, type(uint256).max));
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;
    }

    /// @dev A depositor who is also the fee recipient gets the fee back, which breaks the suite's balance check.
    function setUpVault(Init memory init) public override {
        for (uint256 i; i < N; ++i) {
            vm.assume(init.user[i] != treasury);
        }
        super.setUpVault(init);
    }
}
