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

forge create --private-key 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6 lib/openzeppelin-contracts/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol:ERC20PresetFixedSupply --broadcast --constructor-args "Test token" "TEST" 100000000000000000000 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

kill -2 $anvil_pid
wait
rm anvil_output
