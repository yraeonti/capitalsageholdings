# InstitutionalVault

ERC-4626 tokenized vault built on OpenZeppelin v5.7.0, deployed behind a UUPS proxy.

- **Inflation defense:** virtual shares (offset 6), plus dead shares seeded inside `initialize`
- **Entry fee:** admin-controlled, hard-capped at 500 bps, sent to a fee recipient
- **Deposit cap:** admin-set, reflected in `maxDeposit` / `maxMint`
- **Circuit breaker:** `Pausable` with split roles (fast to pause, admin-only to unpause)

## Quick start

```sh
git clone --recurse-submodules https://github.com/yraeonti/capitalsageholdings.git && cd capitalsageholdings
make all
```

`make all` installs the submodules, builds, runs every test suite and verifies the gas benchmarks against `snapshots/GasBenchmarkTest.json`. It requires [Foundry](https://book.getfoundry.sh/getting-started/installation) `v1.0.0` and `make`. [ARCHITECTURE.md](ARCHITECTURE.md) §4 has the full runbook.

## Layout

```
src/InstitutionalVault.sol         the vault
script/Deploy.s.sol                production (env-driven) and local deployment
test/InstitutionalVault.t.sol      unit + fuzz tests
test/InflationAttack.t.sol         exploit tests against naive, OZ and this vault
test/Upgrade.t.sol                 UUPS upgrade safety
test/ERC4626Compliance.t.sol       a16z ERC-4626 property suite
test/invariant/                    handler-based invariants
test/GasBenchmark.t.sol            gas figures used in ARCHITECTURE.md
```

## What is OpenZeppelin and what is custom

| Component | Source | Notes |
|---|---|---|
| ERC-4626 share math, rounding, `deposit`/`mint`/`withdraw`/`redeem` flow | OZ `ERC4626Upgradeable` | Unmodified. Overridden only through `virtual` hooks. |
| Virtual shares | OZ `_decimalsOffset()` | The vault only chooses the value (6). |
| Roles, two-step admin transfer with delay | OZ `AccessControlDefaultAdminRulesUpgradeable` | Unmodified |
| Pause state | OZ `PausableUpgradeable` | Unmodified |
| Reentrancy guard | OZ `ReentrancyGuardTransient` | Fixed transient-storage slot, so it is proxy-safe |
| Proxy and upgrade authorization | OZ `ERC1967Proxy` + `UUPSUpgradeable` | Unmodified |
| Fee math (`_feeOnTotal`, `_feeOnRaw`, `preview*` overrides, `_deposit` transfer) | OZ `mocks/docs/ERC4626Fees.sol` | Documentation example code, not an audited library contract. The formulas are copied exactly. |
| Dead-share seed inside `initialize` | Custom | |
| Deposit cap and `maxDeposit`/`maxMint` logic | Custom | Added for the "Capped" in the brief's title |
| Pause reflected in all four `max*` functions | Custom | Required by EIP-4626. OZ does not do it by default. |
| Zero-amount reverts | Custom | |
| Fee recipient validation, role split, ERC-7201 namespace | Custom | |

## Test suites

| Suite | Tests | What it proves |
|---|---|---|
| `InstitutionalVault.t.sol` | 39 | All four flows, exact fee values at 0 / 100 / 500 bps, fuzzed rounding, zero amounts, pause, every role check, the cap, initialization |
| `InflationAttack.t.sol` | 5 | The attack succeeds on naive math, is griefing only at offset 0, and is never profitable against this vault (fuzzed) |
| `Upgrade.t.sol` | 5 | State survives an upgrade. Only the upgrader can upgrade. Non-UUPS targets are rejected. Upgrades work while paused. The implementation rejects direct calls. |
| `ERC4626Compliance.t.sol` | 26 | The a16z ERC-4626 property suite, `_delta_ = 0`, with the fee on |
| `invariant/VaultInvariants.t.sol` | 4 | Solvency, share price never decreases, fees match an independent formula, supply equals the sum of holders. 256 runs × 64 calls, `fail_on_revert = true`. |
| `GasBenchmark.t.sol` | 9 | Gas figures, verified against the committed snapshot |

Coverage of `src/InstitutionalVault.sol` (`make coverage`): 100% of lines, statements, branches and functions.

Limits of the evidence:

- The a16z suite discards inputs that make the vault revert, so it does not exercise the zero-amount reverts. The unit tests cover them.
- The compliance harness excludes the fee recipient as a fuzzed caller. A depositor who is also the fee recipient gets the fee back, which breaks the suite's balance assertion. That is a property of the harness, not of the vault.
- Every test uses a standard 6-decimal mock token.

## Assumptions and residual risks

| Topic | Position |
|---|---|
| Asset type | Plain ERC-20 only. Fee-on-transfer and rebasing tokens are not supported: the accounting assumes that `transferFrom(x)` delivers exactly `x`. |
| Reentrancy | OZ ordering (assets in before mint, burn before assets out) plus `nonReentrant` on all four entry points. `view` functions are not guarded, which matters only for assets with transfer hooks. |
| Blacklisted fee recipient | If the asset blacklists the recipient (USDC can), every fee-paying deposit reverts until `FEE_MANAGER_ROLE` sets a new recipient. A pull-based fee removes this dependency, at the cost of one extra storage write per deposit. |
| Zero amounts | All four entry points revert on zero. EIP-4626 allows this, but some integrators call `deposit(0)` as a no-op. |
