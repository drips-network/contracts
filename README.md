# Radicle Drips protocol V2 smart contracts

Radicle Drips is an EVM blockchain protocol for streaming and splitting ERC-20 tokens.
See [docs](https://docs.drips.network) for a high-level introduction and documentation.

# Development
Radicle Drips Hub uses [Foundry](https://github.com/foundry-rs/foundry) for development.
You can install it using [foundryup](https://github.com/foundry-rs/foundry#installation).

The codebase is statically checked with [Slither](https://github.com/crytic/slither) version 0.9.2.
Here are the [installation instructions](https://github.com/crytic/slither#how-to-install).

## Install dependencies
```bash
forge install
```

## Format code
```bash
forge fmt
```

## Run tests
```bash
forge test
```

## Run Slither
```bash
slither .
```

# Deployment

## Deploy to a local testnet
Start a local testnet node and let it run in the background:

```bash
anvil
```

Set up environment variables.
See instructions for public network deployment to see all the options.
To automatically set bare minimum environment variables run:

```bash
source scripts/local-env.sh
```

Run deployment:

```bash
scripts/deploy.sh
```

## Deploy to a public network

Set up environment variables controlling the deployment process:

```bash
# The RPC URL to use, e.g. `https://mainnet.infura.io/MY_INFURA_KEY`.
# Contracts will be deployed to whatever network that endpoint works in.
export ETH_RPC_URL="<URL>"

# Foundry wallet arguments. They will be passed to all commands needing signing.
# Examples:
# "--interactive" - Open an interactive prompt to enter your private key.
# "--private-key <RAW_PRIVATE_KEY>" - Use the provided private key.
# "--mnemonic-path <PATH> --mnemonic-index <INDEX>" - Use the mnemonic file
# "--keystore <PATH> --password <PASSWORD>" - Use the keystore in the given folder or file.
# "--ledger --hd-path <PATH>" - Use a Ledger hardware wallet.
# "--trezor --hd-path <PATH>" - Use a Trezor hardware wallet.
# "--from <ADDRESS>" - Use the Foundry sender account.
# For the full list check Foundry's documentation e.g. by running `cast wallet address --help`.
export WALLET_ARGS="<ARGS>"

# OPTIONAL
# The API key to use to submit contracts' code to Etherscan.
# In case of deployments to networks other than Ethereum an appropriate equivalent service is used.
# If not set, contracts won't be verified.
export ETHERSCAN_API_KEY="<KEY>"

# OPTIONAL
# The JSON file to write deployment addresses to. Default is `./deployment_<NETWORK_NAME>.json`.
export DEPLOYMENT_JSON="<PATH>"
```

Set up environment variables configuring the deployed contracts:

```bash
# OPTIONAL
# Address of the governance of the deployed contracts. If not set, `ETH_FROM` is used.
export GOVERNANCE="<ADDRESS>"

# OPTIONAL
# Address of Caller to use. If not set, a new instance is deployed.
# If set to zero, newly deployed Caller-aware contracts don't get support for Caller.
export CALLER="<ADDRESS>"

# OPTIONAL
# Address of DripsHub to use. If not set, a new instance is deployed.
export DRIPS_HUB="<ADDRESS>"

# OPTIONAL
# Address of the DripsHub admin to set. If not set, `GOVERNANCE` is used.
export DRIPS_HUB_ADMIN="<ADDRESS>"

# OPTIONAL
# Address of the DripsHub logic contract to use in `DRIPS_HUB` when it's deployed.
# If not set, a new instance is deployed.
export DRIPS_HUB_LOGIC="<ADDRESS>"

# OPTIONAL
# Cycle length  to use in `DRIPS_HUB_LOGIC` when it's deployed. Default is 1 week.
export CYCLE_SECS="<SECONDS>"

# OPTIONAL
# Address of AddressDriver to use. If not set, a new instance is deployed for `DRIPS_HUB`.
export ADDRESS_DRIVER="<ADDRESS>"

# OPTIONAL
# Address of the AddressDriver admin to set. If not set, `GOVERNANCE` is used.
export ADDRESS_DRIVER_ADMIN="<ADDRESS>"

# OPTIONAL
# Address of the AddressDriver logic contract to use in `ADDRESS_DRIVER` when it's deployed.
# If not set, a new instance is deployed and a new app ID is registered for `ADDRESS_DRIVER`.
export ADDRESS_DRIVER_LOGIC="<ADDRESS>"

# OPTIONAL
# Address of NFTDriver to use. If not set, a new instance is deployed for `DRIPS_HUB`.
export NFT_DRIVER="<ADDRESS>"

# OPTIONAL
# Address of the NFTDriver admin to set. If not set, `GOVERNANCE` is used.
export NFT_DRIVER_ADMIN="<ADDRESS>"

# OPTIONAL
# Address of the NFTDriver logic contract to use in `NFT_DRIVER` when it's deployed.
# If not set, a new instance is deployed and a new app ID is registered for `NFT_DRIVER`.
export NFT_DRIVER_LOGIC="<ADDRESS>"

# OPTIONAL
# Address of ImmutableSplitsDriver to use. If not set, a new instance is deployed for `DRIPS_HUB`.
export SPLITS_DRIVER="<ADDRESS>"

# OPTIONAL
# Address of the ImmutableSplitsDriver admin to set. If not set, `GOVERNANCE` is used.
export SPLITS_DRIVER_ADMIN="<ADDRESS>"

# OPTIONAL
# Address of the ImmutableSplitsDriver logic contract to use in `SPLITS_DRIVER` when it's deployed.
# If not set, a new instance is deployed and a new app ID is registered for `SPLITS_DRIVER`.
export SPLITS_DRIVER_LOGIC="<ADDRESS>"
```

Run deployment:

```bash
scripts/deploy.sh
```
