.PHONY: all install build test gas gas-update snapshot coverage fmt deploy-local clean

all: install build test gas

install:
	git submodule update --init --recursive

build:
	forge build --sizes

test:
	FORGE_SNAPSHOT_CHECK=true forge test

gas:
	FORGE_SNAPSHOT_CHECK=true forge test --match-contract GasBenchmarkTest
	@cat snapshots/GasBenchmarkTest.json

gas-update:
	forge test --match-contract GasBenchmarkTest

snapshot:
	forge snapshot --no-match-test "testFuzz|invariant" --no-match-contract "ERC4626ComplianceTest"

coverage:
	forge coverage --report summary --no-match-coverage "(test|script)/" --no-match-contract GasBenchmarkTest

fmt:
	forge fmt

deploy-local:
	./script/deploy-local.sh

clean:
	forge clean
