#! /usr/bin/env bash

set -eo pipefail

print_title() {
    echo
    echo -----------------------------------------------------------------------------
    echo "$@"
    echo -----------------------------------------------------------------------------
    echo
}

create() {
    print_title "Creating $1"
    DEPLOYED_ADDR=$( \
        forge create $VERIFY $WALLET_ARGS "$2" --constructor-args "${@:3}" \
        | tee /dev/tty | grep '^Deployed to: ' | cut -d " " -f 3)
}

send() {
    print_title "$1"
    cast send $WALLET_ARGS "$2" "$3" "${@:4}"
}

assertIsDriver() {
    local DRIVER_ID=$(cast call "$2" 'driverId()(uint32)')
    local DRIVER_ID_ADDR=$(cast call "$DRIPS_HUB" 'driverAddress(uint32)(address)' "$DRIVER_ID")
    if [ $(cast --to-checksum-address "$2") != "$DRIVER_ID_ADDR" ]; then
        echo
        echo "$1 not registered as a driver in DripsHub"
        echo "DripsHub address: $DRIPS_HUB"
        echo "$1 ID: $DRIVER_ID"
        echo "$1 address: $DRIVER"
        echo "Driver address registered under ID $DRIVER_ID: $DRIVER_ID_ADDR"
        exit 2
    fi
}

# Set up the defaults
NETWORK=$(cast chain)
DEPLOYMENT_JSON=${DEPLOYMENT_JSON:-./deployment_$NETWORK.json}
DEPLOYER=$(cast wallet address $WALLET_ARGS | cut -d " " -f 2)
GOVERNANCE=${GOVERNANCE:-$DEPLOYER}
RESERVE_OWNER=$(cast --to-checksum-address "${RESERVE_OWNER:-$GOVERNANCE}")
DRIPS_HUB_ADMIN=$(cast --to-checksum-address "${DRIPS_HUB_ADMIN:-$GOVERNANCE}")
ADDRESS_DRIVER_ADMIN=$(cast --to-checksum-address "${ADDRESS_DRIVER_ADMIN:-$GOVERNANCE}")
NFT_DRIVER_ADMIN=$(cast --to-checksum-address "${NFT_DRIVER_ADMIN:-$GOVERNANCE}")
SPLITS_DRIVER_ADMIN=$(cast --to-checksum-address "${SPLITS_DRIVER_ADMIN:-$GOVERNANCE}")
CYCLE_SECS=${CYCLE_SECS:-$(( 7 * 24 * 60 * 60 ))} # 1 week
if [ -n "$ETHERSCAN_API_KEY" ]; then
    VERIFY="--verify"
else
    VERIFY=""
fi

# Print the configuration
print_title "Deployment Config"
echo "Network:                      $NETWORK"
echo "Deployer address:             $DEPLOYER"
if [ -n "$ETHERSCAN_API_KEY" ]; then
    ETHERSCAN_API_KEY_PROVIDED="provided"
else
    ETHERSCAN_API_KEY_PROVIDED="not provided, contracts won't be verified on etherscan"
fi
echo "Etherscan API key:            $ETHERSCAN_API_KEY_PROVIDED"
echo "Deployment JSON:              $DEPLOYMENT_JSON"
TO_DEPLOY="to be deployed"
echo "Caller:                       ${CALLER:-$TO_DEPLOY}"
echo "Reserve:                      ${RESERVE:-$TO_DEPLOY}"
echo "Reserve owner:                $RESERVE_OWNER"
echo "DripsHub:                     ${DRIPS_HUB:-$TO_DEPLOY}"
echo "DripsHub admin:               $DRIPS_HUB_ADMIN"
echo "DripsHub logic:               ${DRIPS_HUB_LOGIC:-$TO_DEPLOY}"
echo "DripsHub cycle seconds:       $CYCLE_SECS"
echo "AddressDriver:                ${ADDRESS_DRIVER:-$TO_DEPLOY}"
echo "AddressDriver admin:          $ADDRESS_DRIVER_ADMIN"
echo "AddressDriver logic:          ${ADDRESS_DRIVER_LOGIC:-$TO_DEPLOY}"
echo "NFTDriver:                    ${NFT_DRIVER:-$TO_DEPLOY}"
echo "NFTDriver admin:              $NFT_DRIVER_ADMIN"
echo "NFTDriver logic:              ${NFT_DRIVER_LOGIC:-$TO_DEPLOY}"
echo "ImmutableSplitsDriver:        ${SPLITS_DRIVER:-$TO_DEPLOY}"
echo "ImmutableSplitsDriver admin:  $SPLITS_DRIVER_ADMIN"
echo "ImmutableSplitsDriver logic:  ${SPLITS_DRIVER_LOGIC:-$TO_DEPLOY}"
echo

read -p "Proceed with deployment? [y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[^Yy] ]]
then
    exit 1
fi

# Deploy the contracts

if [ -z "$CALLER" ]; then
    create "Caller" 'src/Caller.sol:Caller' ""
    CALLER=$DEPLOYED_ADDR
fi

if [ -z "$RESERVE" ]; then
    create "Reserve" 'src/Reserve.sol:Reserve' "$DEPLOYER"
    RESERVE=$DEPLOYED_ADDR
fi

if [ -z "$DRIPS_HUB" ]; then
    if [ -z "$DRIPS_HUB_LOGIC" ]; then
        create "DripsHub logic" 'src/DripsHub.sol:DripsHub' "$CYCLE_SECS" "$RESERVE"
        DRIPS_HUB_LOGIC=$DEPLOYED_ADDR
    fi
    echo "DRIPS_HUB_LOGIC '$DRIPS_HUB_LOGIC'"
    echo "DRIPS_HUB_ADMIN '$DRIPS_HUB_ADMIN'"
    create "DripsHub" 'src/Upgradeable.sol:UpgradeableProxy' "$DRIPS_HUB_LOGIC" "$DRIPS_HUB_ADMIN"
    DRIPS_HUB=$DEPLOYED_ADDR
fi

if [ -z "$ADDRESS_DRIVER" ]; then
    if [ -z "$ADDRESS_DRIVER_LOGIC" ]; then
        NONCE=$(($(cast nonce $DEPLOYER) + 2))
        ADDRESS_DRIVER=$(cast compute-address $DEPLOYER --nonce $NONCE | cut -d " " -f 3)
        ADDRESS_DRIVER_ID=$(cast call "$DRIPS_HUB" 'nextDriverId()(uint32)')
        send "Registering AddressDriver in DripsHub" \
            "$DRIPS_HUB" 'registerDriver(address)(uint32)' "$ADDRESS_DRIVER"
        create "AddressDriver logic" 'src/AddressDriver.sol:AddressDriver' \
            "$DRIPS_HUB" "$CALLER" "$ADDRESS_DRIVER_ID"
        ADDRESS_DRIVER_LOGIC=$DEPLOYED_ADDR
    fi
    create "AddressDriver" 'src/Upgradeable.sol:UpgradeableProxy' \
        "$ADDRESS_DRIVER_LOGIC" "$ADDRESS_DRIVER_ADMIN"
    ADDRESS_DRIVER=$DEPLOYED_ADDR
fi
assertIsDriver "AddressDriver" "$ADDRESS_DRIVER"

if [ -z "$NFT_DRIVER" ]; then
    if [ -z "$NFT_DRIVER_LOGIC" ]; then
        NONCE=$(($(cast nonce $DEPLOYER) + 2))
        NFT_DRIVER=$(cast compute-address $DEPLOYER --nonce $NONCE | cut -d " " -f 3)
        NFT_DRIVER_ID=$(cast call "$DRIPS_HUB" 'nextDriverId()(uint32)')
        send "Registering NFTDriver in DripsHub" \
            "$DRIPS_HUB" 'registerDriver(address)(uint32)' "$NFT_DRIVER"
        create "NFTDriver logic" 'src/NFTDriver.sol:NFTDriver' \
            "$DRIPS_HUB" "$CALLER" "$NFT_DRIVER_ID"
        NFT_DRIVER_LOGIC=$DEPLOYED_ADDR
    fi
    create "NFTDriver" 'src/Upgradeable.sol:UpgradeableProxy' \
        "$NFT_DRIVER_LOGIC" "$NFT_DRIVER_ADMIN"
    NFT_DRIVER=$DEPLOYED_ADDR
fi
assertIsDriver "NFTDriver" "$NFT_DRIVER"

if [ -z "$SPLITS_DRIVER" ]; then
    if [ -z "$SPLITS_DRIVER_LOGIC" ]; then
        NONCE=$(($(cast nonce $DEPLOYER) + 2))
        SPLITS_DRIVER=$(cast compute-address $DEPLOYER --nonce $NONCE | cut -d " " -f 3)
        SPLITS_DRIVER_ID=$(cast call "$DRIPS_HUB" 'nextDriverId()(uint32)')
        send "Registering ImmutableSplitsDriver in DripsHub" \
            "$DRIPS_HUB" 'registerDriver(address)(uint32)' "$SPLITS_DRIVER"
        create "ImmutableSplitsDriver logic" 'src/ImmutableSplitsDriver.sol:ImmutableSplitsDriver' \
            "$DRIPS_HUB" "$SPLITS_DRIVER_ID"
        SPLITS_DRIVER_LOGIC=$DEPLOYED_ADDR
    fi
    create "ImmutableSplitsDriver" 'src/Upgradeable.sol:UpgradeableProxy' \
        "$SPLITS_DRIVER_LOGIC" "$SPLITS_DRIVER_ADMIN"
    SPLITS_DRIVER=$DEPLOYED_ADDR
fi
assertIsDriver "ImmutableSplitsDriver" "$SPLITS_DRIVER"

# Configuring the contracts
if [ $(cast call "$RESERVE" 'isUser(address)(bool)' "$DRIPS_HUB") = "false" ]; then
    send "Adding DripsHub as a Reserve user" \
        "$RESERVE" 'addUser(address)()' "$DRIPS_HUB"
fi

if [ $(cast call "$RESERVE" 'owner()(address)') != "$RESERVE_OWNER" ]; then
    send "Setting Reserve owner to $RESERVE_OWNER" \
        "$RESERVE" 'transferOwnership(address)()' "$RESERVE_OWNER"
fi

if [ $(cast call "$DRIPS_HUB" 'admin()(address)') != "$DRIPS_HUB_ADMIN" ]; then
    send "Setting DripsHub admin to $DRIPS_HUB_ADMIN" \
        "$DRIPS_HUB" 'changeAdmin(address)()' "$DRIPS_HUB_ADMIN"
fi

# Printing the ownership
print_title "Checking contracts ownership"
echo "DripsHub admin:   $(cast call "$DRIPS_HUB" 'admin()(address)')"
echo "Reserve owner:    $(cast call "$RESERVE" 'owner()(address)')"

# Building and printing the deployment JSON
print_title "Deployment JSON: $DEPLOYMENT_JSON"
tee "$DEPLOYMENT_JSON" <<EOF
{
    "Network":                      "$NETWORK",
    "Deployer address":             "$DEPLOYER",
    "Caller":                       "$CALLER",
    "Reserve":                      "$RESERVE",
    "DripsHub":                     "$DRIPS_HUB",
    "DripsHub logic":               "$DRIPS_HUB_LOGIC",
    "DripsHub cycle seconds":       "$CYCLE_SECS",
    "AddressDriver":                "$ADDRESS_DRIVER",
    "AddressDriver logic":          "$ADDRESS_DRIVER_LOGIC",
    "AddressDriver ID":             "$ADDRESS_DRIVER_ID",
    "NFTDriver":                    "$NFT_DRIVER",
    "NFTDriver logic":              "$NFT_DRIVER_LOGIC",
    "NFTDriver ID":                 "$NFT_DRIVER_ID",
    "ImmutableSplitsDriver":        "$SPLITS_DRIVER",
    "ImmutableSplitsDriver logic":  "$SPLITS_DRIVER_LOGIC",
    "ImmutableSplitsDriver ID":     "$SPLITS_DRIVER_ID",
    "Commit hash":                  "$(git rev-parse HEAD)"
}
EOF
