# Radicle Drips protocol V2 smart contracts

Radicle Drips is an EVM blockchain protocol for streaming and splitting ERC-20 tokens.
See [docs](https://docs.drips.network) for a high-level introduction and documentation.

# Development

Radicle Drips uses [Foundry](https://github.com/foundry-rs/foundry) for development.
You can install it using [foundryup](https://github.com/foundry-rs/foundry#installation).

The codebase is statically checked with [Slither](https://github.com/crytic/slither) version 0.11.5.
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

Run deployment:

```bash
forge script -f localhost:8545 --broadcast --slow \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
    script/LocalTestnet.sol:Deploy
```

## Deploying and updating on public networks

Deployments and updates are done using Foundry scripts.
Those scripts are single-use and they are removed after execution to avoid maintenance.
The scripts are never squashed away from the git history and each one can be found in old commits.
Commits used for deployments and updates are marked with git tags, which documents
the state of the protocol code at that point and the scripts that were executed.
