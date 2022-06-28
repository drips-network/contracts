# Radicle Drips Hub Contracts

Radicle Drips Hub is the smart contract running the drips and splits ecosystem.

## Getting started
Radicle Drips Hub uses [dapp.tools](https://github.com/dapphub/dapptools) for development. Please install the `dapp` client. Then, run the following command to install the dependencies:

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
dapp test -m <REGEX>
dapp test -m testName
dapp test -m ':ContractName\.'
```

## Deploy to a local testnet
Start a local testnet node and let it run in the background:

```bash
dapp testnet
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

Use dapp.tools' `ethsign` to query or add keys available on the system for signing transactions.

Set up environment variables controlling the deployment process:

```bash
# The RPC URL to use, e.g. `https://mainnet.infura.io/MY_INFURA_KEY`.
# Contracts will be deployed to whatever network that endpoint works in.
export ETH_RPC_URL="<URL>"

# Address to use for deployment. Must be available in `ethsign`
export ETH_FROM="<ADDRESS>"

# OPTIONAL
# The file containing password to decrypt `ETH_FROM` private key from keystore.
# If not set, the password will be prompted multiple times during deployment.
# If `ETH_FROM` is not password protected, can be set to `/dev/null`.
export ETH_PASSWORD="<KEYSTORE_PASSWORD>"

# OPTIONAL
# The API key to use to submit contracts' code to Etherscan.
# In case of deployments to networks other than Ethereum an appropriate equivalent service is used.
export ETHERSCAN_API_KEY="<KEY>"

# OPTIONAL
# The JSON file to write deployment addresses to. Default is `./deployment_<BLOCKCHAIN_NAME>.json`.
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
```

Run deployment:

```bash
scripts/deploy.sh
```

### Deploying to Polygon Mumbai

Polygon Mumbai is supported by dapp.tools' `seth` in versions **newer than** 0.11.0.
If no such version is officially released yet, you must install it from `master`:

```bash
git clone git@github.com:dapphub/dapptools.git
cd dapptools
nix-env -iA solc dapp seth hevm -f .
```

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
