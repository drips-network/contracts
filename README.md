# Change to trigger the ci
# Radicle Drips Hub Contracts

Radicle Drips Hub is the smart contract running the drips and splits ecosystem.

## Getting started
Radicle Drips Hub uses [foundry](https://github.com/gakonst/foundry) for development. Please install the `forge` client. Then, run the following command to install the dependencies:

```bash
make install
```

### Run all tests
```bash
make test
```

### Run specific tests
A regular expression can be used to only run specific tests.

```bash
forge test --match-test <REGEX_TEST_PATTERN>
forge test --match-contract <REGEX_CONTRACT_PATTERN>
```

### Run linter
```bash
make lint
```

### Run prettier
```bash
make prettier
```
