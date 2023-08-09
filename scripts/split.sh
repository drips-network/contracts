#! /usr/bin/env bash
set -eo pipefail

# Parameters: splits file path
# Env variables: ETH_RPC_URL, WALLET_ARGS, SUBGRAPH_API

# Required programs on the machine: foundry, curl, jq
# This script is standalone, it may be copied and run outside of this repository.

# Each account to be split must be represented in the splits file with a line consisting of
# the token address and the account ID in decimal, white spaces are ignored, for example:
# 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 390153557637010290125401600086462573573670190927
# Lines not following this pattern are ignored, they may be used as comments.

# SUBGRAPH_API is the subgraph API to use to collect information.
# As of writing this script the URL of the subgraph of Drips on Ethereum is:
# https://api.thegraph.com/subgraphs/name/drips-network-dev/drips-on-ethereum

# WALLET_ARGS are the Foundry wallet arguments. They will be passed to all commands needing signing.
# Examples:
# WALLET_ARGS="--interactive" - Open an interactive prompt to enter your private key.
# WALLET_ARGS="--private-key <RAW_PRIVATE_KEY>" - Use the provided private key.
# WALLET_ARGS="--mnemonic-path <PATH> --mnemonic-index <INDEX>" - Use the mnemonic file
# WALLET_ARGS="--keystore <PATH> --password <PASS>" - Use the keystore in the given folder or file.
# WALLET_ARGS="--ledger --mnemonic-derivation-path <PATH>" - Use a Ledger wallet using the HD path.
# WALLET_ARGS="--trezor --mnemonic-derivation-path <PATH>" - Use a Trezor wallet using the HD path.
# WALLET_ARGS="--from <ADDRESS>" - Use the Foundry sender account.
# For the full list check Foundry's documentation e.g. by running `cast wallet address --help`.

# Probably the most convenient way to run the script is to generate an ad-hoc account:
# > cast wallet new
# Then, transfer some funds to that address, and use it in the script:
# > export WALLET_ARGS="--private-key <PRIVATE_KEY>"
# After finishing, send the remaining funds back to the regular wallet:
# > cast balance <ADDRESS>
# > cast send $WALLET_ARGS --value <REMAINING_FUNDS> <YOUR_WALLET>
# Remember to not send the entire balance, the transfer itself needs some funds for gas.

# To test the splitting, run anvil in the forking mode:
# > anvil -f <RPC_URL>
# Then, set the env variables:
# > source scripts/local-env.sh
# To push time forward on the forked chain, e.g. by 1 day, run:
# > cast rpc evm_increaseTime 86400
# > cast send $WALLET_ARGS $(cast address-zero)

# args: subgraph query, jq filter
query_subgraph() {
    curl "$SUBGRAPH_API" -s -X POST -H 'content-type: application/json' -d "{\"query\": \"$1\"}" \
        | jq -r "$2"
}

ADDRESS_DRIVER=$(query_subgraph '{ app(id: 0) { appAddress } }' '.data.app.appAddress')
DRIPS=$(cast call "$ADDRESS_DRIVER" "drips()(address)")
echo "Running on chain $(cast chain) using Drips contract $DRIPS"

RECEIVED_CYCLES=52
SPLITS_FILE_PATTERN='^[[:blank:]]*0x[[:xdigit:]]{40}[[:blank:]]*[[:digit:]]+[[:blank:]]*$'
grep -E "$SPLITS_FILE_PATTERN" "$1" | while read TOKEN ACCOUNT_ID; do
    echo
    echo -----------------------------------------------------------------------------
    echo "Splitting token $TOKEN ($(cast call "$TOKEN" "name()(string)")) for account ID $ACCOUNT_ID"
    echo

    RECEIVABLE=$(cast call "$DRIPS" "receiveStreamsResult(uint256,address,uint32)(uint128)" "$ACCOUNT_ID" "$TOKEN" "$RECEIVED_CYCLES")
    if [ "$RECEIVABLE" == 0 ]; then
        echo "Nothing to receive from streams, skipping."
    else
        echo "$RECEIVABLE receivable from streams, receiving..."
        cast send $WALLET_ARGS "$DRIPS" "receiveStreams(uint256,address,uint32)" "$ACCOUNT_ID" "$TOKEN" "$RECEIVED_CYCLES"
    fi

    echo

    SPLITTABLE=$(cast call "$DRIPS" "splittable(uint256,address)(uint128)" "$ACCOUNT_ID" "$TOKEN")
    if [ "$SPLITTABLE" == 0 ]; then
        echo "Nothing to split, skipping."
    else
        echo "$SPLITTABLE splittable, splitting..."
        SPLITS=$(query_subgraph \
            "{ account(id: \\\"$ACCOUNT_ID\\\") { splitsEntries { accountId, weight}}}" \
            `# First, pad the account IDs to a maximum length with 0s.` \
            `# Then, sort the receivers by the account IDs.` \
            `# Finally, concatenate all the receivers into a single argument for Foundry.` \
            '.data.account.splitsEntries // []
                | map(.accountId |= (78 - (. | length)) * "0" + .)
                | sort_by(.accountId)
                | map("(\(.accountId),\(.weight))") | join(",") | "[\(.)]"
            ')
        cast send $WALLET_ARGS "$DRIPS" "split(uint256,address,(uint256,uint32)[])" "$ACCOUNT_ID" "$TOKEN" "$SPLITS"
    fi
done
