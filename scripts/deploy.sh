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

# Set up the defaults
NETWORK=$(cast chain)
DEPLOYMENT_JSON=${DEPLOYMENT_JSON:-./deployment_$NETWORK.json}
DEPLOYER=$(cast wallet address $WALLET_ARGS | cut -d " " -f 2)
GOVERNANCE=${GOVERNANCE:-$DEPLOYER}
RESERVE_OWNER=$(cast --to-checksum-address ${RESERVE_OWNER:-$GOVERNANCE})
DRIPS_HUB_ADMIN=$(cast --to-checksum-address ${DRIPS_HUB_ADMIN:-$GOVERNANCE})
CYCLE_SECS=${CYCLE_SECS:-$(( 7 * 24 * 60 * 60 ))} # 1 week
if [ -n "$ETHERSCAN_API_KEY" ]; then
    VERIFY="--verify"
else
    VERIFY=""
fi

# Print the configuration
print_title "Deployment Config"
echo "Network:                  $NETWORK"
echo "Deployer address:         $DEPLOYER"
echo "Gas price:                ${ETH_GAS_PRICE:-use the default}"
if [ -n "$ETHERSCAN_API_KEY" ]; then
    ETHERSCAN_API_KEY_PROVIDED="provided"
else
    ETHERSCAN_API_KEY_PROVIDED="not provided, contracts won't be verified on etherscan"
fi
echo "Etherscan API key:        $ETHERSCAN_API_KEY_PROVIDED"
echo "Deployment JSON:          $DEPLOYMENT_JSON"
TO_DEPLOY="to be deployed"
echo "Reserve:                  ${RESERVE:-$TO_DEPLOY}"
echo "Reserve owner:            $RESERVE_OWNER"
echo "DripsHub:                 ${DRIPS_HUB:-$TO_DEPLOY}"
echo "DripsHub admin:           $DRIPS_HUB_ADMIN"
echo "DripsHub logic:           ${DRIPS_HUB_LOGIC:-$TO_DEPLOY}"
echo "DripsHub cycle seconds:   $CYCLE_SECS"
echo "AddressApp:               ${ADDRESS_APP:-$TO_DEPLOY}"
echo

read -p "Proceed with deployment? [y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[^Yy] ]]
then
    exit 1
fi

# Deploy the contracts

if [ -z "$RESERVE" ]; then
    create "Reserve" 'src/Reserve.sol:Reserve' "$DEPLOYER"
    RESERVE=$DEPLOYED_ADDR
fi

if [ -z "$DRIPS_HUB_LOGIC" ]; then
    create "DripsHub logic" 'src/DripsHub.sol:DripsHub' "$CYCLE_SECS" "$RESERVE"
    DRIPS_HUB_LOGIC=$DEPLOYED_ADDR
fi

if [ -z "$DRIPS_HUB" ]; then
    create "DripsHub" 'src/Managed.sol:Proxy' "$DRIPS_HUB_LOGIC" "$DRIPS_HUB_ADMIN"
    DRIPS_HUB=$DEPLOYED_ADDR
fi

if [ -z "$ADDRESS_APP" ]; then
    create "AddressApp" 'src/AddressApp.sol:AddressApp' "$DRIPS_HUB"
    ADDRESS_APP=$DEPLOYED_ADDR
fi

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
    "Network":                  "$NETWORK",
    "Deployer address":         "$DEPLOYER",
    "Reserve":                  "$RESERVE",
    "DripsHub":                 "$DRIPS_HUB",
    "DripsHub logic":           "$DRIPS_HUB_LOGIC",
    "DripsHub cycle seconds":   "$CYCLE_SECS",
    "AddressApp":               "$ADDRESS_APP",
    "Commit hash":              "$(git rev-parse HEAD)"
}
EOF
