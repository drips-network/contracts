#! /usr/bin/env bash

set -eo pipefail

print_title() {
    echo
    echo -----------------------------------------------------------------------------
    echo "$@"
    echo -----------------------------------------------------------------------------
    echo
}

is_set() {
    if [ -n "${!1}" ]; then
        echo "yes"
    else
        echo "no"
    fi
}

verify_parameter() {
    if [ -z "${!1}" ]; then
        echo "Error: '$1' variable not set, see README.md"
        exit 1
    fi
}

# Args: contract name, constructor argument types, constructor arguments
create_module() {
    local SALT="$(cast --format-bytes32-string "$1")"
    local CREATION_CODE="$(forge inspect "src/DripsDeployer.sol:$1Module" bytecode)"
    local TYPES="$2"
    shift 2
    local ARGS="$(cast abi-encode "constructor($TYPES)" "$@")"
    echo "($SALT,0,$(cast --concat-hex "$CREATION_CODE" "$ARGS"))"
}

# Args: module name
module_address() {
    local SALT="$(cast --format-bytes32-string "$1")"
    cast call "$DRIPS_DEPLOYER" "moduleAddress(bytes32)(address)" "$SALT"
}

# Args: module address, field name, field type
query() {
    cast call "$1" "$2()($3)"
}

# Args: contract address, contract path, ABI-encoded constructor args, verifier name
verify_single() {
    echo "Verifying on $4"
    forge verify-contract "$1" "$2" --chain "$CHAIN" --watch --constructor-args "$3" --verifier "$4"
}

# Args: contract address, contract path, ABI-encoded constructor args
verify() {
    echo 1 "$1"
    echo 2 "$2"
    echo 3 "$3"
    if [ -n "$ETHERSCAN_API_KEY" ]; then
        verify_single "$1" "$2" "$3" etherscan
        local VERIFIED=1
    fi
    if [ -n "$VERIFY_SOURCIFY" ]; then
        verify_single "$1" "$2" "$3" sourcify
        local VERIFIED=1
    fi
    if [ -n "$VERIFY_BLOCKSCOUT" ]; then
        verify_single "$1" "$2" "$3" blockscout
        local VERIFIED=1
    fi
    if [ -z "$VERIFIED" ] ; then
        echo "Skipping"
    fi
}

# Args: contract name
# Sets: MODULE_ADDR
verify_module() {
    print_title "Verifying module $1"
    MODULE_ADDR="$(module_address "$1")"
    verify "$MODULE_ADDR" "src/DripsDeployer.sol:$1Module" "$(query "$MODULE_ADDR" args bytes)"
}

# Args: contract name, module address, field name, contract path
verify_module_contract() {
    print_title "Verifying $1 $3"
    verify "$(query "$2" "$3" address)" "$4" "$(query "$2" "$3Args" bytes)"
}

# Args: contract name
verify_contract_deployer_module() {
    verify_module "$1"
    verify_module_contract "$1" "$MODULE_ADDR" deployment "src/$1.sol:$1"
}

# Args: contract name
verify_proxy_deployer_module() {
    verify_module "$1"
    verify_module_contract "$1" "$MODULE_ADDR" logic "src/$1.sol:$1"
    verify_module_contract "$1" "$MODULE_ADDR" proxy "src/Managed.sol:ManagedProxy"
}

deploy_create2_deployer() {
    print_title "Sending funds to the address deploying CREATE2 deployer"
    # Taken from https://github.com/Arachnid/deterministic-deployment-proxy
    cast send $WALLET_ARGS --value "0.01ether" "0x3fAB184622Dc19b6109349B94811493BF2a45362"

    print_title "Deploying the CREATE2 deployer"
    # Taken from https://github.com/Arachnid/deterministic-deployment-proxy
    cast publish "0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7ffffffffffffffff\
fffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b\
8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222\
222222222222222222222222222222222222222222222222222222222"
}

deploy_drips_deployer() {
    print_title "Deploying DripsDeployer"
    local SALT="$(cast --format-bytes32-string "$DRIPS_DEPLOYER_SALT")"
    local CONTRACT_PATH="src/DripsDeployer.sol:DripsDeployer"
    local CREATION_CODE="$(forge inspect "$CONTRACT_PATH" bytecode)"
    local ARGS="$(cast abi-encode "constructor(address)" "$WALLET")"
    local INIT_CODE="$(cast --concat-hex "$CREATION_CODE" "$ARGS")"
    local INIT_CODE_HASH="$(cast keccak "$INIT_CODE")"
    local PAYLOAD="$(cast concat-hex "0xff" "$CREATE2_DEPLOYER" "$SALT" "$INIT_CODE_HASH")"
    local PAYLOAD_HASH="$(cast keccak "$PAYLOAD")"
    DRIPS_DEPLOYER="$(cast --to-checksum-address "0x${PAYLOAD_HASH:26}")"
    if [ "$(cast code "$DRIPS_DEPLOYER")" != "0x" ]; then
        echo "Error: DripsDeployer salt '$DRIPS_DEPLOYER_SALT' has already been used by $WALLET"
        exit 1
    fi
    cast send $WALLET_ARGS "$CREATE2_DEPLOYER" "$(cast --concat-hex "$SALT" "$INIT_CODE")"

    print_title "Verifying DripsDeployer"
    verify "$DRIPS_DEPLOYER" "$CONTRACT_PATH" "$(query "$DRIPS_DEPLOYER" args bytes)"
}

main() {
    verify_parameter ETH_RPC_URL
    verify_parameter WALLET_ARGS

    # Set up the defaults
    if [ $(cast chain-id) == 11155111 ]; then
        CHAIN=sepolia
    else
        CHAIN="$(cast chain)"
    fi
    DEPLOYMENT_JSON=${DEPLOYMENT_JSON:-./deployment_$CHAIN.json}
    WALLET=$(cast wallet address $WALLET_ARGS | cut -d " " -f 2)
    # Taken from https://github.com/Arachnid/deterministic-deployment-proxy
    CREATE2_DEPLOYER="0x4e59b44847b379578588920cA78FbF26c0B4956C"
    unset DEPLOY_CREATE2_DEPLOYER
    if [ -z "$DRIPS_DEPLOYER" ] && [ "$(cast code "$CREATE2_DEPLOYER")" = "0x" ]; then
        DEPLOY_CREATE2_DEPLOYER="will be deployed"
    fi
    DRIPS_DEPLOYER_SALT="${DRIPS_DEPLOYER_SALT:-DripsDeployer}"
    if [ -n "$DRIPS_DEPLOYER" ]; then
        unset DRIPS_DEPLOYER_SALT
    fi
    ADMIN="${ADMIN:-$WALLET}"
    DRIPS_ADMIN="$(cast --to-checksum-address "${DRIPS_ADMIN:-$ADMIN}")"
    ADDRESS_DRIVER_ADMIN="$(cast --to-checksum-address "${ADDRESS_DRIVER_ADMIN:-$ADMIN}")"
    NFT_DRIVER_ADMIN="$(cast --to-checksum-address "${NFT_DRIVER_ADMIN:-$ADMIN}")"
    IMMUTABLE_SPLITS_DRIVER_ADMIN="$(\
        cast --to-checksum-address "${IMMUTABLE_SPLITS_DRIVER_ADMIN:-$ADMIN}")"
    REPO_DRIVER_ADMIN="$(cast --to-checksum-address "${REPO_DRIVER_ADMIN:-$ADMIN}")"
    DRIPS_CYCLE_SECS="${DRIPS_CYCLE_SECS:-$(( 7 * 24 * 60 * 60 ))}" # 1 week
    REPO_DRIVER_OPERATOR="${REPO_DRIVER_OPERATOR:-$(cast --address-zero)}"
    REPO_DRIVER_JOB_ID="${REPO_DRIVER_JOB_ID:-00000000000000000000000000000000}"
    REPO_DRIVER_FEE="${REPO_DRIVER_FEE:-0}"

    # Print the configuration
    print_title "Deployment configuration"
    echo "Chain:                         $CHAIN"
    echo "Wallet:                        $WALLET"
    echo "Etherscan verification:        $(is_set ETHERSCAN_API_KEY)"
    echo "Sourcify verification:         $(is_set VERIFY_SOURCIFY)"
    echo "Blockscout verification:       $(is_set VERIFY_BLOCKSCOUT)"
    echo "Deployment JSON:               $DEPLOYMENT_JSON"
    echo "CREATE2 deployer:              ${DEPLOY_CREATE2_DEPLOYER:-will not be deployed}"
    echo "Deployer:                      ${DRIPS_DEPLOYER:-will be deployed}"
    echo "Deployer salt:                 ${DRIPS_DEPLOYER_SALT:-will not be deployed}"
    echo "Drips cycle seconds:           $DRIPS_CYCLE_SECS"
    echo "Drips admin:                   $DRIPS_ADMIN"
    echo "AddressDriver admin:           $ADDRESS_DRIVER_ADMIN"
    echo "NFTDriver admin:               $NFT_DRIVER_ADMIN"
    echo "ImmutableSplitsDriver admin:   $IMMUTABLE_SPLITS_DRIVER_ADMIN"
    echo "RepoDriver AnyApi operator:    $REPO_DRIVER_OPERATOR"
    echo "RepoDriver AnyApi job ID:      $REPO_DRIVER_JOB_ID"
    echo "RepoDriver AnyApi default fee: $REPO_DRIVER_FEE"
    echo "RepoDriver admin:              $REPO_DRIVER_ADMIN"
    echo

    read -p "Proceed with deployment? [y/n] " -n 1 -r
    echo
    if [[ "$REPLY" =~ ^[^Yy] ]]
    then
        exit 0
    fi

    forge install

    if [ -n "$DEPLOY_CREATE2_DEPLOYER" ]; then
        deploy_create2_deployer
    fi

    if [ -z "$DRIPS_DEPLOYER" ]; then
        deploy_drips_deployer
    fi

    print_title "Deploying contracts"
    MODULE_INIT_CODES_1="[$(
        create_module Drips address,uint32,address \
            "$DRIPS_DEPLOYER" "$DRIPS_CYCLE_SECS" "$DRIPS_ADMIN"
        ),$(
        create_module Caller address "$DRIPS_DEPLOYER"
        ),$(
        create_module AddressDriver address,address "$DRIPS_DEPLOYER" "$ADDRESS_DRIVER_ADMIN"
        )]"
    MODULE_INIT_CODES_2="[$(
        create_module NFTDriver address,address "$DRIPS_DEPLOYER" "$NFT_DRIVER_ADMIN"
        ),$(
        create_module ImmutableSplitsDriver address,address \
            "$DRIPS_DEPLOYER" "$IMMUTABLE_SPLITS_DRIVER_ADMIN"
        )]"
    MODULE_INIT_CODES_3="[$(
        create_module RepoDriver address,address,address,bytes32,uint96 \
            "$DRIPS_DEPLOYER" "$REPO_DRIVER_ADMIN" "$REPO_DRIVER_OPERATOR" \
            $(cast --format-bytes32-string "$REPO_DRIVER_JOB_ID") "$REPO_DRIVER_FEE"
        )]"
    MODULE_INIT_CODES_4="[]"
    cast send $WALLET_ARGS "$DRIPS_DEPLOYER" "deployModules((bytes32,uint256,bytes)[], \
        (bytes32,uint256,bytes)[],(bytes32,uint256,bytes)[],(bytes32,uint256,bytes)[])" \
        "$MODULE_INIT_CODES_1" "$MODULE_INIT_CODES_2" "$MODULE_INIT_CODES_3" "$MODULE_INIT_CODES_4"

    verify_proxy_deployer_module Drips
    local DRIPS_MODULE="$MODULE_ADDR"

    verify_contract_deployer_module Caller
    local CALLER_MODULE="$MODULE_ADDR"

    verify_proxy_deployer_module AddressDriver
    local ADDRESS_DRIVER_MODULE="$MODULE_ADDR"

    verify_proxy_deployer_module NFTDriver
    local NFT_DRIVER_MODULE="$MODULE_ADDR"

    verify_proxy_deployer_module ImmutableSplitsDriver
    local IMMUTABLE_SPLITS_DRIVER_MODULE="$MODULE_ADDR"

    verify_proxy_deployer_module RepoDriver
    local REPO_DRIVER_MODULE="$MODULE_ADDR"

    # Build and print the deployment JSON
    print_title Building the deployment JSON: "$DEPLOYMENT_JSON"
    tee "$DEPLOYMENT_JSON" <<EOF
{
    "Chain":                         "$CHAIN",
    "Deployment time":               "$(date --utc --iso-8601=seconds)",
    "Commit hash":                   "$(git rev-parse HEAD)",
    "Wallet":                        "$WALLET",
    "DripsDeployer":                 "$DRIPS_DEPLOYER",
    "DripsDeployer salt":            "$DRIPS_DEPLOYER_SALT",
    "Drips":                         "$(query "$DRIPS_MODULE" drips address)",
    "Drips cycle seconds":           "$(query "$DRIPS_MODULE" dripsCycleSecs uint32)",
    "Drips logic":                   "$(query "$DRIPS_MODULE" logic address)",
    "Drips admin":                   "$(query "$DRIPS_MODULE" proxyAdmin address)",
    "Caller":                        "$(query "$CALLER_MODULE" caller address)",
    "AddressDriver":                 "$(query "$ADDRESS_DRIVER_MODULE" addressDriver address)",
    "AddressDriver ID":              "$(query "$ADDRESS_DRIVER_MODULE" driverId uint32)",
    "AddressDriver logic":           "$(query "$ADDRESS_DRIVER_MODULE" logic address)",
    "AddressDriver admin":           "$(query "$ADDRESS_DRIVER_MODULE" proxyAdmin address)",
    "NFTDriver":                     "$(query "$NFT_DRIVER_MODULE" nftDriver address)",
    "NFTDriver ID":                  "$(query "$NFT_DRIVER_MODULE" driverId uint32)",
    "NFTDriver logic":               "$(query "$NFT_DRIVER_MODULE" logic address)",
    "NFTDriver admin":               "$(query "$NFT_DRIVER_MODULE" proxyAdmin address)",
    "ImmutableSplitsDriver":         "$(query "$IMMUTABLE_SPLITS_DRIVER_MODULE" immutableSplitsDriver address)",
    "ImmutableSplitsDriver ID":      "$(query "$IMMUTABLE_SPLITS_DRIVER_MODULE" driverId uint32)",
    "ImmutableSplitsDriver logic":   "$(query "$IMMUTABLE_SPLITS_DRIVER_MODULE" logic address)",
    "ImmutableSplitsDriver admin":   "$(query "$IMMUTABLE_SPLITS_DRIVER_MODULE" proxyAdmin address)",
    "RepoDriver":                    "$(query "$REPO_DRIVER_MODULE" repoDriver address)",
    "RepoDriver ID":                 "$(query "$REPO_DRIVER_MODULE" driverId uint32)",
    "RepoDriver AnyApi operator":    "$(query "$REPO_DRIVER_MODULE" operator address)",
    "RepoDriver AnyApi job ID":      "$(cast --parse-bytes32-string "$(query "$REPO_DRIVER_MODULE" jobId bytes32)")",
    "RepoDriver AnyApi default fee": "$(query "$REPO_DRIVER_MODULE" defaultFee uint96)",
    "RepoDriver logic":              "$(query "$REPO_DRIVER_MODULE" logic address)",
    "RepoDriver admin":              "$(query "$REPO_DRIVER_MODULE" proxyAdmin address)"
}
EOF
}

main "$@"
