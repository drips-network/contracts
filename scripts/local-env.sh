#! /usr/bin/env bash

# Define ENV
GETH_DIR=$HOME/.dapp/testnet/8545
mkdir -p $GETH_DIR

# Default Test Config
touch $GETH_DIR/.empty-password

export ETH_RPC_URL=http://127.0.0.1:8545
export ETH_KEYSTORE=$GETH_DIR/keystore
export ETH_PASSWORD=$GETH_DIR/.empty-password
export ETH_FROM=0x$(cat $GETH_DIR/keystore/* | jq -r '.address' | head -n 1)
export ETH_GAS=10000000
