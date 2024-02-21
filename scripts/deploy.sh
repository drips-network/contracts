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

deploy_deterministic_deployer() {
    print_title "Sending funds to the address deploying deterministic deployer"
    # Taken from https://github.com/Arachnid/deterministic-deployment-proxy
    cast send $WALLET_ARGS --value "0.01ether" "0x3fAB184622Dc19b6109349B94811493BF2a45362"

    print_title "Deploying deterministic deployer"
    # Taken from https://github.com/Arachnid/deterministic-deployment-proxy
    cast publish "0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7ffffffffffffffff\
fffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b\
8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222\
222222222222222222222222222222222222222222222222222222222"
}

deploy_create3_factory() {
    print_title "Deploying CREATE3 factory"
    # Taken from https://github.com/ZeframLou/create3-factory,
    # originally deployed to https://etherscan.io/address/0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf
    # in https://etherscan.io/tx/0xb05de371a18fc4f02753b34a689939cee69b93a043b926732043780959b7c4e3,
    # this is the input data of this transaction, which is the contract's init code.
    # It's reused verbatim to keep it byte-for-byte identical across all deployments and chains,
    # so deterministic deployer always deploys it under the same address,
    # even if we upgrade the compiler or change its configuration.
    local INIT_CODE="0x608060405234801561001057600080fd5b5061063b806100206000396000f3fe608060405260\
0436106100295760003560e01c806350f1c4641461002e578063cdcb760a14610077575b600080fd5b34801561003a57600\
080fd5b5061004e610049366004610489565b61008a565b60405173ffffffffffffffffffffffffffffffffffffffff9091\
16815260200160405180910390f35b61004e6100853660046104fd565b6100ee565b6040517ffffffffffffffffffffffff\
fffffffffffffffff000000000000000000000000606084901b166020820152603481018290526000906054016040516020\
818303038152906040528051906020012091506100e78261014c565b9392505050565b6040517ffffffffffffffffffffff\
fffffffffffffffffff0000000000000000000000003360601b166020820152603481018390526000906054016040516020\
818303038152906040528051906020012092506100e78383346102b2565b604080518082018252601081527f67363d3d373\
63d34f03d5260086018f30000000000000000000000000000000060209182015290517fff00000000000000000000000000\
000000000000000000000000000000000000918101919091527fffffffffffffffffffffffffffffffffffffffff0000000\
000000000000000003060601b166021820152603581018290527f21c35dbe1b344a2488cf3321d6ce542f8e9f305544ff09\
e4993a62319a497c1f60558201526000908190610228906075015b604051602081830303815290604052805190602001209\
0565b6040517fd69400000000000000000000000000000000000000000000000000000000000060208201527fffffffffff\
ffffffffffffffffffffffffffffff000000000000000000000000606083901b1660228201527f010000000000000000000\
000000000000000000000000000000000000000000060368201529091506100e79060370161020f565b6000806040518060\
400160405280601081526020017f67363d3d37363d34f03d5260086018f3000000000000000000000000000000008152509\
0506000858251602084016000f5905073ffffffffffffffffffffffffffffffffffffffff811661037d576040517f08c379\
a000000000000000000000000000000000000000000000000000000000815260206004820152601160248201527f4445504\
c4f594d454e545f4641494c454400000000000000000000000000000060448201526064015b60405180910390fd5b610386\
8661014c565b925060008173ffffffffffffffffffffffffffffffffffffffff1685876040516103b091906105d6565b600\
06040518083038185875af1925050503d80600081146103ed576040519150601f19603f3d011682016040523d82523d6000\
602084013e6103f2565b606091505b50509050808015610419575073ffffffffffffffffffffffffffffffffffffffff841\
63b15155b61047f576040517f08c379a0000000000000000000000000000000000000000000000000000000008152602060\
04820152601560248201527f494e495449414c495a4154494f4e5f4641494c4544000000000000000000000060448201526\
06401610374565b5050509392505050565b6000806040838503121561049c57600080fd5b823573ffffffffffffffffffff\
ffffffffffffffffffff811681146104c057600080fd5b946020939093013593505050565b7f4e487b71000000000000000\
00000000000000000000000000000000000000000600052604160045260246000fd5b600080604083850312156105105760\
0080fd5b82359150602083013567ffffffffffffffff8082111561052f57600080fd5b818501915085601f8301126105435\
7600080fd5b813581811115610555576105556104ce565b604051601f82017fffffffffffffffffffffffffffffffffffff\
ffffffffffffffffffffffffffe0908116603f0116810190838211818310171561059b5761059b6104ce565b81604052828\
1528860208487010111156105b457600080fd5b826020860160208301376000602084830101528095505050505050925092\
9050565b6000825160005b818110156105f757602081860181015185830152016105dd565b5060009201918252509190505\
6fea2646970667358221220fd377c185926b3110b7e8a544f897646caf36a0e82b2629de851045e2a5f937764736f6c6343\
0008100033"
    local SALT=$(cast to-bytes32 0)
    cast send $WALLET_ARGS "$DETERMINISTIC_DEPLOYER" "$(cast concat-hex "$SALT" "$INIT_CODE")"
}

drips_deployer() {
    local GET_DEPLOYED="getDeployed(address deployer, bytes32 salt)(address deployed)"
    local SALT="$(cast format-bytes32-string "$DRIPS_DEPLOYER_SALT")"
    cast call "$CREATE3_FACTORY" "$GET_DEPLOYED" "$WALLET" "$SALT"
}

deploy_drips_deployer() {
    print_title "Deploying DripsDeployer"
    DRIPS_DEPLOYER=$(drips_deployer)
    local DEPLOY="deploy(bytes32 salt, bytes initCode)"
    local SALT="$(cast format-bytes32-string "$DRIPS_DEPLOYER_SALT")"
    local CREATION_CODE="$(forge inspect "src/DripsDeployer.sol:DripsDeployer" bytecode)"
    local ARGS="$(cast abi-encode "constructor(address)" "$WALLET")"
    local INIT_CODE="$(cast concat-hex "$CREATION_CODE" "$ARGS")"
    cast send $WALLET_ARGS "$CREATE3_FACTORY" "$DEPLOY" "$SALT" "$INIT_CODE"
}

deploy_modules() {
    print_title "Deploying modules"
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
            $(cast format-bytes32-string "$REPO_DRIVER_JOB_ID") "$REPO_DRIVER_FEE"
        )]"
    MODULE_INIT_CODES_4="[]"
    cast send $WALLET_ARGS "$DRIPS_DEPLOYER" "deployModules((bytes32,uint256,bytes)[], \
        (bytes32,uint256,bytes)[],(bytes32,uint256,bytes)[],(bytes32,uint256,bytes)[])" \
        "$MODULE_INIT_CODES_1" "$MODULE_INIT_CODES_2" "$MODULE_INIT_CODES_3" "$MODULE_INIT_CODES_4"
}

# Args: contract name, constructor argument types, constructor arguments
create_module() {
    local SALT="$(cast format-bytes32-string "$1")"
    local CREATION_CODE="$(forge inspect "src/DripsDeployer.sol:$1Module" bytecode)"
    local TYPES="$2"
    shift 2
    local ARGS="$(cast abi-encode "constructor($TYPES)" "$@")"
    local INIT_CODE="$(cast concat-hex "$CREATION_CODE" "$ARGS")"
    echo "($SALT,0,$INIT_CODE)"
}

print_deployment_json() {
    print_title Building the deployment JSON: "$DEPLOYMENT_JSON"
    local DRIPS_MODULE="$(module_address Drips)"
    local CALLER_MODULE="$(module_address Caller)"
    local ADDRESS_DRIVER_MODULE="$(module_address AddressDriver)"
    local NFT_DRIVER_MODULE="$(module_address NFTDriver)"
    local IMMUTABLE_SPLITS_DRIVER_MODULE="$(module_address ImmutableSplitsDriver)"
    local REPO_DRIVER_MODULE="$(module_address RepoDriver)"
    tee "$DEPLOYMENT_JSON" <<EOF
{
    "Chain":                         "$CHAIN",
    "Deployment time":               "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "Commit hash":                   "$(git rev-parse HEAD)",
    "Wallet":                        "$WALLET",
    "Deterministic deployer":        "$DETERMINISTIC_DEPLOYER",
    "CREATE3 factory":               "$CREATE3_FACTORY",
    "DripsDeployer salt":            "$DRIPS_DEPLOYER_SALT",
    "DripsDeployer":                 "$DRIPS_DEPLOYER",
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
    "RepoDriver AnyApi job ID":      "$(cast parse-bytes32-string "$(query "$REPO_DRIVER_MODULE" jobId bytes32)")",
    "RepoDriver AnyApi default fee": "$(query "$REPO_DRIVER_MODULE" defaultFee uint96)",
    "RepoDriver logic":              "$(query "$REPO_DRIVER_MODULE" logic address)",
    "RepoDriver admin":              "$(query "$REPO_DRIVER_MODULE" proxyAdmin address)"
}
EOF
}

# Args: module name
module_address() {
    local SALT="$(cast format-bytes32-string "$1")"
    cast call "$DRIPS_DEPLOYER" "moduleAddress(bytes32)(address)" "$SALT"
}

# Args: module address, field name, field type
query() {
    cast call "$1" "$2()($3)"
}

main() {
    export FOUNDRY_PROFILE=optimized

    verify_parameter ETH_RPC_URL
    verify_parameter WALLET_ARGS
    verify_parameter DRIPS_DEPLOYER_SALT

    # Set up the defaults
    if [ $(cast chain-id) == 11155111 ]; then
        CHAIN=sepolia
    else
        CHAIN="$(cast chain)"
    fi
    WALLET=$(cast wallet address $WALLET_ARGS | cut -d " " -f 2)

    DEPLOYMENT_JSON=${DEPLOYMENT_JSON:-./deployment_$CHAIN.json}
    ADMIN="${ADMIN:-$WALLET}"
    DRIPS_ADMIN="$(cast to-check-sum-address "${DRIPS_ADMIN:-$ADMIN}")"
    ADDRESS_DRIVER_ADMIN="$(cast to-check-sum-address "${ADDRESS_DRIVER_ADMIN:-$ADMIN}")"
    NFT_DRIVER_ADMIN="$(cast to-check-sum-address "${NFT_DRIVER_ADMIN:-$ADMIN}")"
    IMMUTABLE_SPLITS_DRIVER_ADMIN="$(\
        cast to-check-sum-address "${IMMUTABLE_SPLITS_DRIVER_ADMIN:-$ADMIN}")"
    REPO_DRIVER_ADMIN="$(cast to-check-sum-address "${REPO_DRIVER_ADMIN:-$ADMIN}")"
    DRIPS_CYCLE_SECS="${DRIPS_CYCLE_SECS:-$(( 7 * 24 * 60 * 60 ))}" # 1 week
    REPO_DRIVER_OPERATOR="${REPO_DRIVER_OPERATOR:-$(cast address-zero)}"
    REPO_DRIVER_JOB_ID="${REPO_DRIVER_JOB_ID:-00000000000000000000000000000000}"
    REPO_DRIVER_FEE="${REPO_DRIVER_FEE:-0}"

    # Taken from https://github.com/Arachnid/deterministic-deployment-proxy
    DETERMINISTIC_DEPLOYER="0x4e59b44847b379578588920cA78FbF26c0B4956C"
    # Always the same, see `deploy_create3_factory`
    CREATE3_FACTORY="0x6aa3d87e99286946161dca02b97c5806fc5ed46f"

    DEPLOY_DETERMINISTIC_DEPLOYER="will be deployed"
    DEPLOY_CREATE3_FACTORY="will be deployed"
    DEPLOY_DRIPS_DEPLOYER="will be deployed"
    DEPLOY_MODULES="will be deployed"
    if [ "$(cast code "$DETERMINISTIC_DEPLOYER")" != "0x" ]; then
        DEPLOY_DETERMINISTIC_DEPLOYER="" # Do not deploy
        if [ "$(cast code "$CREATE3_FACTORY")" != "0x" ]; then
            DEPLOY_CREATE3_FACTORY="" # Do not deploy
            DRIPS_DEPLOYER=$(drips_deployer)
            if [ "$(cast code "$DRIPS_DEPLOYER")" != "0x" ]; then
                DEPLOY_DRIPS_DEPLOYER="" # Do not deploy
                if [ "$(cast call "$DRIPS_DEPLOYER" "moduleSalts()(bytes32[])")" != "[]" ]; then
                    DEPLOY_MODULES="" # Do not deploy
                fi
            fi
        fi
    fi

    print_title "Deployment configuration"
    echo "Chain:                         $CHAIN"
    echo "Wallet:                        $WALLET"
    echo "Etherscan verification:        $(is_set ETHERSCAN_API_KEY)"
    echo "Sourcify verification:         $(is_set VERIFY_SOURCIFY)"
    echo "Blockscout verification:       $(is_set VERIFY_BLOCKSCOUT)"
    echo "Deployment JSON:               $DEPLOYMENT_JSON"
    echo "Deterministic deployer:        ${DEPLOY_DETERMINISTIC_DEPLOYER:-already deployed}"
    echo "CREATE3 factory:               ${DEPLOY_CREATE3_FACTORY:-already deployed}"
    echo "DripsDeployer salt:            $DRIPS_DEPLOYER_SALT"
    echo "DripsDeployer:                 ${DEPLOY_DRIPS_DEPLOYER:-already deployed}"
    echo "Modules:                       ${DEPLOY_MODULES:-already deployed}"
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

    echo "Proceed with deployment? [y/n]"
    while true
    do
        read -r -s -n 1
        case "$REPLY" in
            Y | y ) break ;;
            N | n ) exit 0 ;;
        esac
    done

    print_title "Building the contracts"
    forge build --skip test

    if [ -n "$DEPLOY_DETERMINISTIC_DEPLOYER" ]; then
        deploy_deterministic_deployer
    fi

    if [ -n "$DEPLOY_CREATE3_FACTORY" ]; then
        deploy_create3_factory
    fi

    if [ -n "$DEPLOY_DRIPS_DEPLOYER" ]; then
        deploy_drips_deployer
    fi

    if [ -n "$DEPLOY_MODULES" ]; then
        deploy_modules
    fi

    print_deployment_json

    if [ -n "$ETHERSCAN_API_KEY" ] || [ -n "$VERIFY_SOURCIFY" ] || [ -n "$VERIFY_BLOCKSCOUT" ]; then
        scripts/verify.sh "$DRIPS_DEPLOYER"
    fi
}

main "$@"
