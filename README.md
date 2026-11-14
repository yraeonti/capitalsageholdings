# InstitutionalVault

ERC-4626 tokenized vault built on OpenZeppelin v5.7.0, deployed behind a UUPS proxy.

- **Inflation defense:** virtual shares (offset 6), plus dead shares seeded inside `initialize`
- **Entry fee:** admin-controlled, hard-capped at 500 bps, sent to a fee recipient
- **Deposit cap:** admin-set, reflected in `maxDeposit` / `maxMint`
- **Circuit breaker:** `Pausable` with split roles (fast to pause, admin-only to unpause)

## Quick start

```sh
git clone --recurse-submodules <repo-url> && cd institutional-vault
make all
```

`make all` installs the submodules, builds, runs every test suite and prints the gas benchmarks. It requires [Foundry](https://book.getfoundry.sh/getting-started/installation) and `make`.

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

## Documentation

[ARCHITECTURE.md](ARCHITECTURE.md) covers:

- the accounting flow
- the threat model, with measured attack results
- the upgradeability and storage design
- the role model and emergency runbook
- gas and the full command reference
