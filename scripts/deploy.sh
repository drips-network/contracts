#! /usr/bin/env bash

set -eo pipefail

print_title() {
    echo
    echo -----------------------------------------------------------------------------
    echo "$@"
    echo -----------------------------------------------------------------------------
    echo
}

# Verify parameters
verify_parameter() {
    if [ -z "${!1}" ]; then
        echo Error: "'$1'" variable not set, see README.md
        exit 1
    fi
}
verify_parameter ETH_RPC_URL
verify_parameter WALLET_ARGS

# Set up the defaults
CHAIN=$(cast chain)
DEPLOYMENT_JSON=${DEPLOYMENT_JSON:-./deployment_$CHAIN.json}
WALLET=$(cast wallet address $WALLET_ARGS | cut -d " " -f 2)
WALLET_NONCE=$(cast nonce "$WALLET")
ADMIN=${ADMIN:-$WALLET}
DRIPS_HUB_ADMIN=$(cast --to-checksum-address "${DRIPS_HUB_ADMIN:-$ADMIN}")
ADDRESS_DRIVER_ADMIN=$(cast --to-checksum-address "${ADDRESS_DRIVER_ADMIN:-$ADMIN}")
NFT_DRIVER_ADMIN=$(cast --to-checksum-address "${NFT_DRIVER_ADMIN:-$ADMIN}")
SPLITS_DRIVER_ADMIN=$(cast --to-checksum-address "${SPLITS_DRIVER_ADMIN:-$ADMIN}")
DRIPS_HUB_CYCLE_SECS=${DRIPS_HUB_CYCLE_SECS:-$(( 7 * 24 * 60 * 60 ))} # 1 week

# Print the configuration
print_title Deployment configuration
echo "Chain:                        $CHAIN"
echo "Wallet:                       $WALLET"
echo "Wallet nonce:                 $WALLET_NONCE"
ETHERSCAN_API_KEY_PROVIDED="not provided, contracts won't be verified on Etherscan"
if [ -n "$ETHERSCAN_API_KEY" ]; then
    ETHERSCAN_API_KEY_PROVIDED="provided"
fi
echo "Etherscan API key:            $ETHERSCAN_API_KEY_PROVIDED"
echo "Deployment JSON:              $DEPLOYMENT_JSON"
echo "DripsHub cycle seconds:       $DRIPS_HUB_CYCLE_SECS"
echo "DripsHub admin:               $DRIPS_HUB_ADMIN"
echo "AddressDriver admin:          $ADDRESS_DRIVER_ADMIN"
echo "NFTDriver admin:              $NFT_DRIVER_ADMIN"
echo "ImmutableSplitsDriver admin:  $SPLITS_DRIVER_ADMIN"
echo

read -p "Proceed with deployment? [y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[^Yy] ]]
then
    exit 0
fi

# Deploy the smart contracts
print_title Deploying the smart contracts
forge install
VERIFY=""
if [ -n "$ETHERSCAN_API_KEY" ]; then
    VERIFY="--verify"
fi
DEPLOYER=$( \
    forge create $VERIFY $WALLET_ARGS "src/Deployer.sol:Deployer" --constructor-args \
        "$DRIPS_HUB_CYCLE_SECS" \
        "$DRIPS_HUB_ADMIN" \
        "$ADDRESS_DRIVER_ADMIN" \
        "$NFT_DRIVER_ADMIN" \
        "$SPLITS_DRIVER_ADMIN" \
    | tee /dev/tty | grep '^Deployed to: ' | cut -d " " -f 3)
deployment_detail() {
    cast call "$DEPLOYER" "$1()($2)"
}

# Verify the smart contracts
if [ -n "$ETHERSCAN_API_KEY" ]; then
    verify() {
        print_title Verifying "$1"
        local ADDRESS=$(deployment_detail $1 address)
        local ARGS=$(deployment_detail $1Args bytes)
        forge verify-contract "$ADDRESS" "$2" --chain "$CHAIN" --watch --constructor-args "$ARGS"
    }
    verifyWithProxy() {
        verify "$1Logic" "$2"
        verify "$1" "src/Managed.sol:ManagedProxy"
    }
    verifyWithProxy dripsHub src/DripsHub.sol:DripsHub
    verify caller src/Caller.sol:Caller
    verifyWithProxy addressDriver src/AddressDriver.sol:AddressDriver
    verifyWithProxy nftDriver src/NFTDriver.sol:NFTDriver
    verifyWithProxy immutableSplitsDriver src/ImmutableSplitsDriver.sol:ImmutableSplitsDriver
fi

# Build and print the deployment JSON
print_title Building the deployment JSON: "$DEPLOYMENT_JSON"
tee "$DEPLOYMENT_JSON" <<EOF
{
    "Chain":                        "$CHAIN",
    "Deployment time":              "$(date --utc --iso-8601=seconds)",
    "Commit hash":                  "$(git rev-parse HEAD)",
    "Wallet":                       "$WALLET",
    "Wallet nonce":                 "$WALLET_NONCE",
    "Deployer":                     "$DEPLOYER",
    "DripsHub":                     "$(deployment_detail dripsHub address)",
    "DripsHub cycle seconds":       "$(deployment_detail dripsHubCycleSecs uint32)",
    "DripsHub logic":               "$(deployment_detail dripsHubLogic address)",
    "DripsHub admin":               "$(deployment_detail dripsHubAdmin address)",
    "Caller":                       "$(deployment_detail caller address)",
    "AddressDriver":                "$(deployment_detail addressDriver address)",
    "AddressDriver logic":          "$(deployment_detail addressDriverLogic address)",
    "AddressDriver admin":          "$(deployment_detail addressDriverAdmin address)",
    "AddressDriver ID":             "$(deployment_detail addressDriverId uint32)",
    "NFTDriver":                    "$(deployment_detail nftDriver address)",
    "NFTDriver logic":              "$(deployment_detail nftDriverLogic address)",
    "NFTDriver admin":              "$(deployment_detail nftDriverAdmin address)",
    "NFTDriver ID":                 "$(deployment_detail nftDriverId uint32)",
    "ImmutableSplitsDriver":        "$(deployment_detail immutableSplitsDriver address)",
    "ImmutableSplitsDriver logic":  "$(deployment_detail immutableSplitsDriverLogic address)",
    "ImmutableSplitsDriver admin":  "$(deployment_detail immutableSplitsDriverAdmin address)",
    "ImmutableSplitsDriver ID":     "$(deployment_detail immutableSplitsDriverId uint32)"
}
EOF
