// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {InstitutionalVault} from "../src/InstitutionalVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PlainVault} from "./mocks/PlainVault.sol";
import {VaultDeployer} from "./utils/VaultDeployer.sol";

/// @dev One operation per test, so each measurement starts with cold storage.
contract GasBenchmarkTest is VaultDeployer {
    MockERC20 internal usdc;
    InstitutionalVault internal vault;
    InstitutionalVault internal vaultNoFee;
    PlainVault internal plain;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = _deployVault(usdc, 100, type(uint256).max);
        _fund(alice);
        _fund(bob);
        vm.prank(alice);
        vault.deposit(10_000e6, alice);

        vaultNoFee = _deployVault(usdc, 0, type(uint256).max);
        vm.startPrank(alice);
        usdc.approve(address(vaultNoFee), type(uint256).max);
        vaultNoFee.deposit(10_000e6, alice);
        vm.stopPrank();
        vm.prank(bob);
        usdc.approve(address(vaultNoFee), type(uint256).max);

        plain = new PlainVault(IERC20(address(usdc)), 6);
        vm.startPrank(alice);
        usdc.approve(address(plain), type(uint256).max);
        plain.deposit(10_000e6, alice);
        vm.stopPrank();
        vm.prank(bob);
        usdc.approve(address(plain), type(uint256).max);
    }

    function test_gas_baselinePlainOzDepositNewHolder() public {
        vm.prank(bob);
        plain.deposit(10_000e6, bob);
        vm.snapshotGasLastCall("baseline_plain_oz_deposit_new_holder");
    }

    function test_gas_depositNewHolderZeroFee() public {
        vm.prank(bob);
        vaultNoFee.deposit(10_000e6, bob);
        vm.snapshotGasLastCall("deposit_new_holder_zero_fee");
    }

    function _fund(address user) internal {
        usdc.mint(user, 1_000_000e6);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    function test_gas_depositNewHolder() public {
        vm.prank(bob);
        vault.deposit(10_000e6, bob);
        vm.snapshotGasLastCall("deposit_new_holder");
    }

    function test_gas_depositExistingHolder() public {
        vm.prank(alice);
        vault.deposit(10_000e6, alice);
        vm.snapshotGasLastCall("deposit_existing_holder");
    }

    function test_gas_mintExistingHolder() public {
        vm.prank(alice);
        vault.mint(1e12, alice);
        vm.snapshotGasLastCall("mint_existing_holder");
    }

    function test_gas_withdrawPartial() public {
        vm.prank(alice);
        vault.withdraw(1_000e6, alice, alice);
        vm.snapshotGasLastCall("withdraw_partial");
    }

    function test_gas_redeemFull() public {
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vault.redeem(shares, alice, alice);
        vm.snapshotGasLastCall("redeem_full");
    }

    function test_gas_pause() public {
        vm.prank(pauser);
        vault.pause();
        vm.snapshotGasLastCall("pause");
    }

    function test_gas_setDepositFee() public {
        vm.prank(feeManager);
        vault.setDepositFee(250);
        vm.snapshotGasLastCall("setDepositFee");
    }
}
