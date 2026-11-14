#!/usr/bin/env bash
set -euo pipefail
ANVIL_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
anvil --silent --port 8545 &
ANVIL_PID=$!
trap 'kill $ANVIL_PID' EXIT
sleep 1
forge script script/Deploy.s.sol:Deploy --sig "runLocal()" --rpc-url http://127.0.0.1:8545 --broadcast --private-key "$ANVIL_KEY"
