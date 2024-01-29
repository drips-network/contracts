#! /usr/bin/env bash
set -eo pipefail

# Parameters: splits file path
# Env variables: ETH_RPC_URL, WALLET_ARGS, SUBGRAPH_API

# Required programs on the machine: foundry, curl, jq
# This script is standalone, it may be copied and run outside of this repository.

# The file is read line by line, with white spaces ignored.
# Whenever a line with an address is found, it's assumed to be an ERC-20 address, which from this
# point will be used for processing accounts until the next ERC-20 address is found, for example:
# 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
# The token address may be followed by the minimum amount to be processed, for example:
# 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 1.5
# Whenever a line with only a decimal number is found, it's assumed to be an account ID,
# which will be processed for the currently used token, for example:
# 390153557637010290125401600086462573573670190927
# Lines not following these patterns are ignored, they may be used as comments.

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

verify_parameter() {
    if [ -z "${!1}" ]; then
        echo "Error: '$1' variable not set"
        exit 1
    fi
}

# args: subgraph query, jq filter
query_subgraph() {
    curl "$SUBGRAPH_API" -s -X POST -H 'content-type: application/json' -d "{\"query\": \"$1\"}" \
        | jq -r "$2"
}

# args: amount
pretty_amt() {
    echo $(cast to-fixed-point "$DECIMALS" "$1") $SYMBOL
}

# args: address, minimum amount (optional)
process_token() {
    local TOKEN="$1"
    local MIN_AMT_RAW="$2"
    local DECIMALS=$(cast call "$TOKEN" "decimals()(uint8)" | cut -f 1 -d " ")
    local MIN_AMT=0
    if [ -n "$MIN_AMT_RAW" ]; then
        MIN_AMT=$(cast from-fixed-point "$DECIMALS" "$MIN_AMT_RAW")
    fi
    ALL_TOKENS+=("$TOKEN")
    ALL_DECIMALS+=("$DECIMALS")
    ALL_SYMBOLS+=("$(cast call "$TOKEN" "symbol()(string)" | sed 's/^"//;s/"$//')")
    ALL_NAMES+=("$(cast call "$TOKEN" "name()(string)" | sed 's/^"//;s/"$//')")
    ALL_MIN_AMTS+=("$MIN_AMT")
}

# args: amount
is_below_min_amt() {
    if [ "$1" == 0 ]; then
        return 0
    fi
    local AMT_FLOAT=$(cast to-fixed-point 18 "$1")
    local AMT_HIGH=$(echo "$AMT_FLOAT" | sed 's/\..*//')
    local AMT_LOW=$(echo "$AMT_FLOAT" | sed 's/[^.]*\.//')
    local MIN_FLOAT=$(cast to-fixed-point 18 "$MIN_AMT")
    local MIN_HIGH=$(echo "$MIN_FLOAT" | sed 's/\..*//')
    local MIN_LOW=$(echo "$MIN_FLOAT" | sed 's/[^.]*\.//')
    if [ "$AMT_HIGH" == "$MIN_HIGH" ]; then
        [ "$AMT_LOW" -lt "$MIN_LOW" ]
    else
        [ "$AMT_HIGH" -lt "$MIN_HIGH" ]
    fi
}

# args: account ID
process_account() {
    ACCOUNT_ID="$1"
    echo
    echo =============================================================================
    echo
    echo "Processing account ID $ACCOUNT_ID"
    for i in "${!ALL_TOKENS[@]}"; do
        TOKEN=${ALL_TOKENS[i]}
        DECIMALS=${ALL_DECIMALS[i]}
        SYMBOL=${ALL_SYMBOLS[i]}
        NAME=${ALL_NAMES[i]}
        MIN_AMT=${ALL_MIN_AMTS[i]}
        echo
        echo -----------------------------------------------------------------------------
        echo
        echo "Using token $TOKEN ($NAME)"
        echo "The minimum amount to process is $(pretty_amt "$MIN_AMT")"
        process_account_for_token
    done
}

process_account_for_token() {
    # Receive streams
    local CYCLES=52
    RECEIVABLE=$(cast call "$DRIPS" "receiveStreamsResult(uint256,address,uint32)(uint128)" "$ACCOUNT_ID" "$TOKEN" "$CYCLES" | cut -f 1 -d " ")
    echo
    if is_below_min_amt "$RECEIVABLE" ; then
        echo "$(pretty_amt "$RECEIVABLE") receivable from streams, skipping."
    else
        echo "$(pretty_amt "$RECEIVABLE") receivable from streams, receiving..."
        cast send $WALLET_ARGS "$DRIPS" "receiveStreams(uint256,address,uint32)" "$ACCOUNT_ID" "$TOKEN" "$CYCLES"
    fi
    echo

    # Split
    SPLITTABLE=$(cast call "$DRIPS" "splittable(uint256,address)(uint128)" "$ACCOUNT_ID" "$TOKEN" | cut -f 1 -d " ")
    if is_below_min_amt "$SPLITTABLE" ; then
        echo "$(pretty_amt "$SPLITTABLE") splittable, skipping."
    else
        echo "$(pretty_amt "$SPLITTABLE") splittable, splitting..."
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
}

verify_parameter ETH_RPC_URL
verify_parameter WALLET_ARGS
verify_parameter SUBGRAPH_API

unset TOKEN
ADDRESS_DRIVER=$(query_subgraph '{ app(id: 0) { appAddress } }' '.data.app.appAddress')
DRIPS=$(cast call "$ADDRESS_DRIVER" "drips()(address)" | cut -f 1 -d " ")
echo "Running on chain $(cast chain) using Drips contract $DRIPS"

cat "$1" | while read FIRST SECOND; do
    if (echo "$FIRST" | grep -Eq '^0x[[:xdigit:]]{40}$'); then
        process_token "$FIRST" "$SECOND"
    elif (echo "$FIRST" | grep -Eq '^[[:digit:]]+$') && [ -z "$SECOND" ]; then
        process_account "$FIRST"
    fi
done
