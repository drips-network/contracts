# Radicle Streaming Contracts


## Getting started
Radicle Streaming uses [dapp.tools](https://github.com/dapphub/dapptools) for development. Please install the `dapp` client. Then, run the following command to install the dependencies:

```bash 
dapp update
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


### Env Variables
The contracts are developed with the following configuration dapp tools configuration.
```bash
export DAPP_TEST_TIMESTAMP=0
export DAPP_SOLC_VERSION=0.7.6
export DAPP_BUILD_OPTIMIZE=1
export DAPP_SRC="contracts"
```
