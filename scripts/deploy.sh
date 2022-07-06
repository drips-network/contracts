#! /usr/bin/env bash

set -e

message() {

    echo
    echo -----------------------------------------------------------------------------
    echo "$@"
    echo -----------------------------------------------------------------------------
    echo
}

addValuesToFile() {
    result=$(jq -s add "$1" /dev/stdin)
    printf %s "$result" > "$1"
}

deploy() {
    echo -e "Deploying $1\n"
    DEPLOYED_ADDR=$(dapp create "$2" "${@:3}")
    echo -e "\nDeployed $1 to $DEPLOYED_ADDR\n"

    if [ -n "$ETHERSCAN_API_KEY" ]
    then
        echo -e "Verifying $1 on Etherscan\n"
        sleep 10 # give etherscan some time to process the block
        dapp verify-contract --async "$2" "$DEPLOYED_ADDR" "${@:3}"
    else
        echo -e "ETHERSCAN_API_KEY not provided, skipping Etherscan verification\n"
    fi
}

# Set up the defaults
DEPLOYMENT_JSON=${DEPLOYMENT_JSON:-./deployment_$(seth chain).json}
GOVERNANCE=${GOVERNANCE:-$ETH_FROM}
RESERVE_OWNER=${RESERVE_OWNER:-$GOVERNANCE}
DRIPS_HUB_ADMIN=${DRIPS_HUB_ADMIN:-$GOVERNANCE}
CYCLE_SECS=${CYCLE_SECS:-$(( 7 * 24 * 60 * 60 ))} # 1 week

# Print the configuration
message Deployment Config
echo "Network:                  $(seth chain)"
echo "Deployer address:         $ETH_FROM"
echo "Gas price:                ${ETH_GAS_PRICE:-use the default}"
ETHERSCAN_API_KEY_PROVIDED=${ETHERSCAN_API_KEY:+provided}
echo "Etherscan API key:        ${ETHERSCAN_API_KEY_PROVIDED:-not provided}"
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

read -p "Ready to deploy? [y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[^Yy] ]]
then
    exit 1
fi

# Build the contracts
message Building Contracts
dapp build

# Deploy the contracts
message Deploying contracts

if [ -z "$RESERVE" ]; then
    deploy "Reserve" 'src/Reserve.sol:Reserve' "$ETH_FROM"
    RESERVE=$DEPLOYED_ADDR
fi

if [ -z "$DRIPS_HUB_LOGIC" ]; then
    deploy "DripsHub logic" 'src/DripsHub.sol:DripsHub' "$CYCLE_SECS" "$RESERVE"
    DRIPS_HUB_LOGIC=$DEPLOYED_ADDR
fi

if [ -z "$DRIPS_HUB" ]; then
    deploy "DripsHub" 'src/Managed.sol:Proxy' "$DRIPS_HUB_LOGIC" "$DRIPS_HUB_ADMIN"
    DRIPS_HUB=$DEPLOYED_ADDR
fi

if [ -z "$ADDRESS_APP" ]; then
    deploy "AddressApp" 'src/AddressApp.sol:AddressApp' "$DRIPS_HUB"
    ADDRESS_APP=$DEPLOYED_ADDR
fi

# Configuring the contracts
if [ $(seth call "$RESERVE" 'isUser(address)(bool)' "$DRIPS_HUB") = "false" ]; then
    echo -e "Adding DripsHub as a Reserve user\n"
    seth send "$RESERVE" 'addUser(address)()' "$DRIPS_HUB"
    echo
fi

if [ $(seth call "$RESERVE" 'owner()(address)') != $(seth --to-address $RESERVE_OWNER) ]; then
    echo -e "Setting Reserve owner to $RESERVE_OWNER\n"
    seth send "$RESERVE" 'transferOwnership(address)()' "$RESERVE_OWNER"
    echo
fi

if [ $(seth call "$DRIPS_HUB" 'admin()(address)') != $(seth --to-address $DRIPS_HUB_ADMIN) ]; then
    echo -e "Setting DripsHub admin to $DRIPS_HUB_ADMIN\n"
    seth send "$DRIPS_HUB" 'changeAdmin(address)()' "$DRIPS_HUB_ADMIN"
    echo
fi

# Printing the ownership
message Checking contracts ownership
echo "DripsHub admin:   $(seth call $DRIPS_HUB 'admin()(address)')"
echo "Reserve owner:    $(seth call $RESERVE 'owner()(address)')"

# Building the deployment JSON
touch $DEPLOYMENT_JSON
addValuesToFile $DEPLOYMENT_JSON <<EOF
{
    "Network":                  "$(seth chain)",
    "Deployer address":         "$ETH_FROM",
    "Reserve":                  "$RESERVE",
    "DripsHub":                 "$DRIPS_HUB",
    "DripsHub logic":           "$DRIPS_HUB_LOGIC",
    "DripsHub cycle seconds":   "$CYCLE_SECS",
    "AddressApp":               "$ADDRESS_APP",
    "Commit hash":              "$(git --git-dir .git rev-parse HEAD )"
}
EOF

# Printing the deployment JSON
message Deployment JSON: $DEPLOYMENT_JSON
cat $DEPLOYMENT_JSON
echo
