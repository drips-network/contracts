# Radicle Streaming Contracts


## Getting started
Radicle Streaming uses [dapp.tools](https://github.com/dapphub/dapptools) for development. Please install the `dapp` client. Then, run the following command to install the dependencies:

```bash
dapp update
```

### Run all tests
```bash
dapp test
```

### Run specific tests
A regular expression can be used to only run specific tests.

```bash
dapp test -m <REGEX>
dapp test -m testName
dapp test -m ':ContractName\.'
```
