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
