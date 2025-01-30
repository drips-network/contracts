#!/bin/bash
set -euxo pipefail

echo Deploying contracts to anvil...

mkdir anvil-data

mkfifo anvil_output

anvil --dump-state ./anvil-state.json --host 0.0.0.0 > anvil_output 2>&1 &
anvil_pid=$!

while ! grep -q "Listening on 0.0.0.0:8545" < anvil_output; do
  sleep 1
done

forge script -f localhost:8545 --broadcast --slow --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 script/LocalTestnet.sol:Deploy

kill -2 $anvil_pid
wait
rm anvil_output
