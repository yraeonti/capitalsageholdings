.PHONY: all install build test gas snapshot coverage fmt deploy-local clean

all: install build test gas

install:
	git submodule update --init --recursive

build:
	forge build --sizes

test:
	forge test

gas:
	forge test --match-contract GasBenchmarkTest
	@cat snapshots/GasBenchmarkTest.json

snapshot:
	forge snapshot --no-match-test "testFuzz|invariant" --no-match-contract "ERC4626ComplianceTest"

coverage:
	forge coverage --report summary --no-match-coverage "(test|script)/"

fmt:
	forge fmt

deploy-local:
	./script/deploy-local.sh

clean:
	forge clean
