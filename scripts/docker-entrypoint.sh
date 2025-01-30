#!/bin/bash

printf "\n💧 Drips contracts are deployed at: \n"

cat ./deployment.json
printf "\n\n"

printf "🪙 Test ERC 20 is deployed at:\n"

printf "0x700b6A60ce7EaaEA56F065753d8dcB9653dbAD35 \n\n"

printf "🪙 Address 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 has 100000000000000000000 TEST.\n\n"

printf "Starting testnet...\n\n"

# if ./anvil-data/anvil-state.json does not exist, copy it from ./anvil-state.json. Else, log that it already exists.
if [ ! -f ./anvil-data/anvil-state.json ]; then
  printf "Anvil state does not exist. Initializing fresh anvil state\n"
  cp ./anvil-state.json ./anvil-data/anvil-state.json
else
  printf "Anvil state already exists. Using existing state in /anvil-data/\n"
fi

exec anvil --load-state ./anvil-data/anvil-state.json --dump-state ./anvil-data/anvil-state.json --host 0.0.0.0 --block-time 1
