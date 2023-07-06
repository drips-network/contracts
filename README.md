# Radicle Drips protocol V2 smart contracts

Radicle Drips is an EVM blockchain protocol for streaming and splitting ERC-20 tokens.
See [docs](https://docs.drips.network) for a high-level introduction and documentation.

# Development
Radicle Drips uses [Foundry](https://github.com/foundry-rs/foundry) for development.
You can install it using [foundryup](https://github.com/foundry-rs/foundry#installation).

The codebase is statically checked with [Slither](https://github.com/crytic/slither) version 0.9.5.
Here are the [installation instructions](https://github.com/crytic/slither#how-to-install).

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
# If set, submits contracts' code to Sourcify.
# In case of deployments to networks other than Ethereum an appropriate equivalent service is used.
# If not set, contracts won't be verified.
export VERIFY_SOURCIFY=1

# OPTIONAL
# If set, submits contracts' code to Blockscout.
# In case of deployments to networks other than Ethereum an appropriate equivalent service is used.
# If not set, contracts won't be verified.
export VERIFY_BLOCKSCOUT=1

# OPTIONAL
# The JSON file to write deployment addresses to. Default is `./deployment_<NETWORK_NAME>.json`.
export DEPLOYMENT_JSON="<PATH>"
```

Set up environment variables configuring the deployed contracts:

```bash
# OPTIONAL
# Address of the deployed contracts admin to set. If not set, the deployer's wallet address is used.
export ADMIN="<ADDRESS>"

# OPTIONAL
# The salt used for the deployment of a DripsDeployer instance. If not set, `DripsDeployer` is used.
export DRIPS_DEPLOYER_SALT="<SALT>"

# OPTIONAL
# Cycle length  to use in `DRIPS_LOGIC` when it's deployed. If not set, 1 week is used.
export DRIPS_CYCLE_SECS="<SECONDS>"

# OPTIONAL
# Address of the Drips admin to set. If not set, `ADMIN` is used.
export DRIPS_ADMIN="<ADDRESS>"

# OPTIONAL
# Address of the AddressDriver admin to set. If not set, `ADMIN` is used.
export ADDRESS_DRIVER_ADMIN="<ADDRESS>"

# OPTIONAL
# Address of the NFTDriver admin to set. If not set, `ADMIN` is used.
export NFT_DRIVER_ADMIN="<ADDRESS>"

# OPTIONAL
# Address of the ImmutableSplitsDriver admin to set. If not set, `ADMIN` is used.
export IMMUTABLE_SPLITS_DRIVER_ADMIN="<ADDRESS>"

# OPTIONAL
# The address of the AnyApi operator. If not set, zero address is used.
export REPO_DRIVER_OPERATOR="<ADDRESS>"

# OPTIONAL
# The AnyApi job ID used for requesting account owner updates.
# If not set, a string of zeros is used.
export REPO_DRIVER_JOB_ID="<JOB_ID>"

# OPTIONAL
# The fee in Link for each account owner. If not set, `0` is used.
export REPO_DRIVER_FEE="<FEE>"

# OPTIONAL
# Address of the RepoDriver admin to set. If not set, `ADMIN` is used.
export REPO_DRIVER_ADMIN="<ADDRESS>"
```

Run deployment:

```bash
scripts/deploy.sh
```

## Verify and publish source code of an existing deployment

The deployment may not be verified, either because the deployer chose to do that,
or because the verification process failed, as it randomly happens.
Verification can be done separately for any deployment as long as the
repository is checked out at the right commit.

Set up environment variables controlling the deployment process:

```bash
# The RPC URL to use, e.g. `https://mainnet.infura.io/MY_INFURA_KEY`.
# Contracts will be deployed to whatever network that endpoint works in.
export ETH_RPC_URL="<URL>"

# OPTIONAL
# The API key to use to submit contracts' code to Etherscan.
# In case of deployments to networks other than Ethereum an appropriate equivalent service is used.
# If not set, contracts won't be verified.
export ETHERSCAN_API_KEY="<KEY>"

# OPTIONAL
# If set, submits contracts' code to Sourcify.
# In case of deployments to networks other than Ethereum an appropriate equivalent service is used.
# If not set, contracts won't be verified.
export VERIFY_SOURCIFY=1

# OPTIONAL
# If set, submits contracts' code to Blockscout.
# In case of deployments to networks other than Ethereum an appropriate equivalent service is used.
# If not set, contracts won't be verified.
export VERIFY_BLOCKSCOUT=1
```

At least one of `ETHERSCAN_API_KEY`, `VERIFY_SOURCIFY` and `VERIFY_BLOCKSCOUT` must be set.

Run verification:

```bash
scripts/verify.sh <DRIPS_DEPLOYER>
```

The `DRIPS_DEPLOYER` parameter is the `DripsDeployer` contract address,
it can be found in the deployment JSON.
