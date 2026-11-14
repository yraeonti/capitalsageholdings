// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {InstitutionalVault} from "../src/InstitutionalVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PlainVault} from "./mocks/PlainVault.sol";
import {NaiveVault} from "./mocks/NaiveVault.sol";
import {VaultDeployer} from "./utils/VaultDeployer.sol";

contract InflationAttackTest is VaultDeployer {
    MockERC20 internal usdc;
    address internal attacker = makeAddr("attacker");
    address internal victim = makeAddr("victim");

    uint256 internal constant VICTIM_DEPOSIT = 10_000e6;

    struct Outcome {
        int256 attackerPnl;
        int256 victimPnl;
        uint256 victimShares;
    }

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    /// @dev Attacker deposits 1 wei, donates `donation`, victim deposits, both exit.
    function _attack(IERC4626 vault, uint256 donation) internal returns (Outcome memory o) {
        uint256 attackerStart = 1 + donation;
        usdc.mint(attacker, attackerStart);
        usdc.mint(victim, VICTIM_DEPOSIT);

        vm.startPrank(attacker);
        usdc.approve(address(vault), type(uint256).max);
        vault.deposit(1, attacker);
        usdc.transfer(address(vault), donation);
        vm.stopPrank();

        vm.startPrank(victim);
        usdc.approve(address(vault), type(uint256).max);
        o.victimShares = vault.deposit(VICTIM_DEPOSIT, victim);
        if (o.victimShares > 0) vault.redeem(o.victimShares, victim, victim);
        vm.stopPrank();

        uint256 attackerShares = vault.balanceOf(attacker);
        vm.prank(attacker);
        vault.redeem(attackerShares, attacker, attacker);

        o.attackerPnl = int256(usdc.balanceOf(attacker)) - int256(attackerStart);
        o.victimPnl = int256(usdc.balanceOf(victim)) - int256(VICTIM_DEPOSIT);
    }

    function _defended() internal returns (IERC4626) {
        return IERC4626(address(_deployVault(usdc, 0, type(uint256).max)));
    }

    function test_attack_stealsVictimDepositOnNaiveVault() public {
        Outcome memory o = _attack(new NaiveVault(IERC20(address(usdc))), VICTIM_DEPOSIT);

        assertEq(o.victimShares, 0);
        assertEq(o.victimPnl, -int256(VICTIM_DEPOSIT));
        assertEq(o.attackerPnl, int256(VICTIM_DEPOSIT));
    }

    function test_attack_offsetZeroTurnsTheftIntoGriefing() public {
        Outcome memory o = _attack(new PlainVault(IERC20(address(usdc)), 0), VICTIM_DEPOSIT);

        assertEq(o.victimShares, 1);
        assertLt(o.attackerPnl, 0);
        assertLt(o.victimPnl, 0);
    }

    function test_attack_isUnprofitableAgainstInstitutionalVault() public {
        Outcome memory o = _attack(_defended(), VICTIM_DEPOSIT);

        assertGt(o.victimShares, 0);
        assertLt(o.attackerPnl, 0);
        assertGe(o.victimPnl, -1);
    }

    function testFuzz_attack_neverProfitableAgainstInstitutionalVault(uint256 donation) public {
        donation = bound(donation, 1, 1_000_000_000e6);
        Outcome memory o = _attack(_defended(), donation);

        assertGt(o.victimShares, 0);
        assertLe(o.attackerPnl, 0);
    }

    function test_attack_reportByDefense() public {
        uint256 snap0 = vm.snapshotState();
        Outcome memory n = _attack(new NaiveVault(IERC20(address(usdc))), VICTIM_DEPOSIT);
        console2.log("naive (no virtual shares)");
        console2.log("  attacker pnl", n.attackerPnl);
        console2.log("  victim pnl  ", n.victimPnl);
        vm.revertToState(snap0);

        uint8[3] memory offsets = [0, 3, 6];
        for (uint256 i; i < offsets.length; ++i) {
            uint256 snap = vm.snapshotState();
            Outcome memory p = _attack(new PlainVault(IERC20(address(usdc)), offsets[i]), VICTIM_DEPOSIT);
            console2.log("offset", offsets[i]);
            console2.log("  attacker pnl", p.attackerPnl);
            console2.log("  victim pnl  ", p.victimPnl);
            vm.revertToState(snap);
        }
        Outcome memory d = _attack(_defended(), VICTIM_DEPOSIT);
        console2.log("InstitutionalVault (offset 6 + seed)");
        console2.log("  attacker pnl", d.attackerPnl);
        console2.log("  victim pnl  ", d.victimPnl);
    }
}
