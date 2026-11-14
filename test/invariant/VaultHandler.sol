// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {InstitutionalVault} from "../../src/InstitutionalVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract VaultHandler is Test {
    InstitutionalVault internal immutable vault;
    MockERC20 internal immutable asset;
    address internal immutable feeManager;

    address[] public actors;
    uint256 public expectedFees;
    bool public priceDecreased;

    constructor(InstitutionalVault vault_, MockERC20 asset_, address feeManager_) {
        vault = vault_;
        asset = asset_;
        feeManager = feeManager_;
        for (uint256 i; i < 3; ++i) {
            address a = makeAddr(string.concat("actor", vm.toString(i)));
            actors.push(a);
            asset.mint(a, 1_000_000e6);
            vm.prank(a);
            asset.approve(address(vault), type(uint256).max);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    modifier trackPrice() {
        uint256 a0 = vault.totalAssets() + 1;
        uint256 s0 = vault.totalSupply() + 1e6;
        _;
        uint256 a1 = vault.totalAssets() + 1;
        uint256 s1 = vault.totalSupply() + 1e6;
        if (a1 * s0 < a0 * s1) priceDecreased = true;
    }

    function deposit(uint256 seed, uint256 assets) external trackPrice {
        address a = actors[seed % actors.length];
        uint256 balance = asset.balanceOf(a);
        if (balance < 2) return;
        assets = bound(assets, 2, balance);
        uint16 bps = vault.depositFeeBps();
        expectedFees += (assets * bps + bps + 10_000 - 1) / (bps + 10_000);
        vm.prank(a);
        vault.deposit(assets, a);
    }

    function mint(uint256 seed, uint256 shares) external trackPrice {
        address a = actors[seed % actors.length];
        uint256 maxShares = vault.convertToShares(asset.balanceOf(a)) / 2;
        if (maxShares == 0) return;
        shares = bound(shares, 1, maxShares);
        if (vault.previewMint(shares) > asset.balanceOf(a)) return;
        uint256 net = _ceilDiv(shares * (vault.totalAssets() + 1), vault.totalSupply() + 1e6);
        expectedFees += _ceilDiv(net * vault.depositFeeBps(), 10_000);
        vm.prank(a);
        vault.mint(shares, a);
    }

    function withdraw(uint256 seed, uint256 assets) external trackPrice {
        address a = actors[seed % actors.length];
        uint256 max = vault.maxWithdraw(a);
        if (max == 0) return;
        assets = bound(assets, 1, max);
        vm.prank(a);
        vault.withdraw(assets, a, a);
    }

    function redeem(uint256 seed, uint256 shares) external trackPrice {
        address a = actors[seed % actors.length];
        uint256 max = vault.maxRedeem(a);
        if (max == 0) return;
        shares = bound(shares, 1, max);
        if (vault.previewRedeem(shares) == 0) return;
        vm.prank(a);
        vault.redeem(shares, a, a);
    }

    function donate(uint256 assets) external {
        asset.mint(address(vault), bound(assets, 1, 100_000e6));
    }

    function setFee(uint256 bps) external {
        vm.prank(feeManager);
        vault.setDepositFee(uint16(bound(bps, 0, 500)));
    }

    function _ceilDiv(uint256 x, uint256 y) private pure returns (uint256) {
        return x == 0 ? 0 : (x - 1) / y + 1;
    }
}
