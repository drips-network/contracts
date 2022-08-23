# Radicle Drips Hub Contracts

Radicle Drips Hub is the smart contract running the drips and splits ecosystem.

## Getting started
Radicle Drips Hub uses [Foundry](https://github.com/foundry-rs/foundry) for development.
You can install it using [foundryup](https://github.com/foundry-rs/foundry#installation).
Then, run the following command to install the dependencies:

```bash
make install
```

### Run linter
```bash
make lint
```

### Run prettier
```bash
make prettier
```

### Run all tests
```bash
make test
```

### Run specific tests
A regular expression can be used to only run specific tests.

```bash
forge test -m <REGEX>
forge test -m testName
forge test -m ':ContractName\.'
```

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
# Address of Reserve to use. If not set, a new instance is deployed.
export RESERVE="<ADDRESS>"

# OPTIONAL
# Address of Reserve owner to set. If not set, `GOVERNANCE` is used.
export RESERVE_OWNER="<ADDRESS>"

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
# Address of AddressApp to use. If not set, a new instance is deployed for `DRIPS_HUB`.
export ADDRESS_APP="<ADDRESS>"

# OPTIONAL
# Address of the AddressApp admin to set. If not set, `GOVERNANCE` is used.
export ADDRESS_APP_ADMIN="<ADDRESS>"

# OPTIONAL
# Address of the AddressApp logic contract to use in `ADDRESS_APP` when it's deployed.
# If not set, a new instance is deployed and a new app ID is registered for `ADDRESS_APP`.
export ADDRESS_APP_LOGIC="<ADDRESS>"
```

Run deployment:

```bash
scripts/deploy.sh
```

### Deploying to Polygon Mumbai

As of now gas estimation isn't working and you need to set it manually to an arbitrary high value:

```bash
export ETH_GAS=10000000
```

For deployment you can use the public MaticVigil RPC endpoint:

```bash
export ETH_RPC_URL='https://rpc-mumbai.maticvigil.com/'
```

To publish smart contracts to `https://mumbai.polygonscan.com/` you need to
use the API key generated for an account on regular `https://polygonscan.com/`.
