# Overview

`RepoDriver` is the Drips protocol driver providing accounts for off-chain entities like git repositories and web2 user accounts. The real world ownership state is not applied on-chain automatically. A signed ownership claim must be explicitly requested from the oracle, then submitted on-chain and only then the on-chain ownership is updated to reflect the real world state. The oracle is executed on Lit network, which provides permissionless trustless MPC and built-in signing keys management.

## The oracle API

The oracle code is built by simply concatenating the official minified build of `js-yaml` 4.1.1 and `litAction.js`. When executing this code must be provided to Lit network verbatim or as its IPFS hash for nodes to fetch.

The oracle Lit Action requires passing `jsParams` object with the following fields:

- `chains` - an array of strings with chain names for which claims should be looked up for.
- `source` - an object with a string `kind` holding the name of the source to look up. There also may be extra fields required by the specific source kind.

The oracle generates a signature for each chain name for which it managed to create an ownership claim. The name of each signature is the chain name.

The oracle returns an object with the following fields:

- `owners` - a mapping from the chain name string to a hex string with the address of the owner for that chain. Only chains for which claims were created and signed are present.
- `sourceId` - the ID of the source that was looked up.
- `name` - the source-specific name for which the claims were looked up.
- `timestamp` - the Unix timestamp since when the claims are known to be true.

## Submitting ownership claims to `RepoDriver`

`RepoDriver` exposes function `updateOwnerByLit` that anybody can call to submit a claim and update the address owning an account. The function requires arguments `sourceId`, `name`, `owner` and `timestamp` describing a claim as returned by the oracle, with `r` and `vs` of the signature. The `owner` and the signature must be taken from the oracle response for the same chain name as the called instance of `RepoDriver` expects.

The signature is verified to be made by a specific implementation of the oracle executed on a specific Lit network. This is possible because the oracle's private key is derived from its source code hash and the Lit network name, and `RepoDriver` only accept signatures made by a single private key. The address derived from the trusted key can be looked up in `RepoDriver` by calling function `litOracle()`.

`RepoDriver` will only accept claims that are strictly newer than the last claim used on the account ID, but not newer than the current timestamp of the blockchain. By default all accounts with no claimed ownerships or claimed before `RepoDriver` was migrated to Lit-based oracle have their timestamp 0. Signatures never expire and have no nonces, monotonic timestamps are the only acceptance condition.

## Chain name

A chain name is a UTF-8 string, by convention formatted as `camelCase` and different for each `RepoDriver` deployment on each chain. The desired chain name can be looked up in the `RepoDriver` contract by calling function `chain()` which returns a `bytes32` containing a UTF-8 string right-padded with zero bytes. This name is used to identify claims applicable in the corresponding `RepoDriver`. 

## Account IDs

Account IDs controlled by `RepoDriver` are 256-bit values built by concatenating:

```
driverId (32 bits) | sourceId (7 bits) | isHash (1 bit) | nameEncoded (216 bits)
```

- `driverId` is the driver ID used by `RepoDriver` in Drips protocol. It can be looked up in the `RepoDriver` contract by calling `driverId()`.
- `sourceId` is the ID of the source as returned by the oracle. 
- `isHash` is a boolean indicating that the name is longer than 27 bytes and is hashed instead of being used verbatim.
- `nameEncoded` is the source-specific name as returned by the oracle. It's right-padded with zeros for names up to 27 bytes and for longer ones it's the right-most 27 bytes of the keccak256 hash.

# Using the oracle manually

This repository provides basic tools for using the oracle manually. You need `npm` on your machine and run `npm install` while in the `oracle` directory. There are several available commands.

## Getting the deployment

To get the deployment details, run `npm run getDeployment`. It will print the oracle IPFS hash of the oracle code and optionally write its content to a file if the output file path is passed as the argument, e.g. `npm run getDeployment ./oracle_code.js`. This command also prints the addresses derived from the oracle's private keys that will be used for signing claims. Each Lit network where the oracle may be executed has a separate address because each of them generates a different private key.

## Depositing tokens for fees

There are currently 3 versions of Lit network with varying levels of being for tests only: naga-dev centralized and with no fees, naga-test decentralized with testLPX token fees and naga-mainnet decentralized with LITKEY token fees. All fees are charged automatically from tokens deposited using the execution requester's wallet. To deposit tokens, run `npm run deposit <amount>` where `<amount>` is the number of whole tokens to deposit, e.g. `1.8`. Use environment variable `ETHEREUM_PRIVATE_KEY` to pass the private key of the wallet holding tokens to be deposited and which will be able to use the deposit to cover Lit protocol fees. The network where the tokens will be deposited is controlled by the environment variable `NETWORK`, set `NETWORK=test` to deposit testLPX on naga-test and `NETWORK=naga` to deposit LITKEY on naga-mainnet. TestLPX tokens can be obtained from the [faucet](https://chronicle-yellowstone-faucet.getlit.dev) and LITKEY can be bought on the market, see the [official tips](https://naga.developer.litprotocol.com/governance/litkey/getting-litkey).

## Querying the oracle

To query the oracle run `npm run query<source> <args> <chains>` where `<source>` is the source name, `<args>` are the source-specific arguments and `<chains>` is a list of chain names to look up, e.g. `npm run queryGitHub drips-network/contracts ethereum optimism`. In the console there will be printed all the arguments that need to be submitted on-chain to update the account ownership. Use environment variable `ETHEREUM_PRIVATE_KEY` to pass the private key of a wallet with deposited tokens to cover Lit protocol fees. Use environment variable `NETWORK` to control which network to execute the oracle on. Set `NETWORK=dev` for `naga-dev`, which is the default when `NETWORK` is unset and does not require any deposited tokens. Use `NETWORK=test` for naga-test using testLPX and `NETWORK=naga` for naga-mainnet using LITKEY. Remember that the same oracle running on different networks will use different private keys for signing claims, so each instance of `RepoDriver` only accepts signatures made using a specific oracle code executed on a specific network.

# Common mechanisms

Here are documented some common mechanisms used by the oracle across various sources.

## Claiming a repository

The repository must be public, it must contain [FUNDING.json](#fundingjson) file in its root directory accessible when checking out the tip commit of the default branch. Anybody can request the oracle to generate claims for any repository. If `FUNDING.json` is nonexistent, removed, malformed or the repository is non-public or nonexistent, ownerships for all chains are considered to be the zero address.

The `source` argument must have an extra `name` string with the canonical repository name in format `<owner>/<repository>`, e.g. `drips-network/contracts`. The returned `name` is the copy of the `name` passed as the argument and `timestamp` is the timestamp of when the lookup was made.

## `FUNDING.json`

For some sources the oracle looks up the `FUNDING.json` file. It parses this document content as a JSON and looks up the string under `drips` -> chain name -> `ownedBy` and then parses it as an EIP-55 checksummed address. If the ownership claim can't be found under the requested chain's `ownedBy` field or if it's malformed (e.g. invalidly checksummed), the claimed address is considered to be the zero address. `FUNDING.json` can contain any data, the oracle will ignore all the unexpected fields. When `FUNDING.json` is modified, lookups will start yielding the new ownerships.

A minimal example of `FUNDING.json`:
```json
{
    "drips": {
        "ethereum": {
            "ownedBy": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
        },
        "optimism": {
            "ownedBy": "0x220866B1A2219f40e72f5c628B65D54268cA3A9D"
        }
    }
}
```

## Ownership URLs

For some sources the oracle parses ownership URLs. A valid ownership URL must be exactly `http://0.0.0.0/DRIPS_OWNERSHIP_CLAIM` and may be followed by search params. The search params define the ownership addresses where the key is the chain name and the value must be the EIP-55 checksummed address. If the ownership claim can't be found under the requested chain name or if it's malformed (e.g. invalidly checksummed), no claim is generated and signed, so the on-chain ownership won't be updated. An invalid ownership URL is considered holding no ownership claims. If there is more than 1 claim for a given chain, valid or malformed, in a single or across multiple URLs parsed by the oracle, no claims are generated for that chain.

A minimal example of an ownership URL:
```
http://0.0.0.0/DRIPS_OWNERSHIP_CLAIM?ethereum=0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045&optimism=0x220866B1A2219f40e72f5c628B65D54268cA3A9D
```

# GitHub

## Claiming a repository

See [Claiming a repository](#claiming-a-repository). The `source` argument must have `kind` field set to `gitHub` and the returned `sourceId` is `0`.

## Claiming a user or an organization

The `source` argument must have `kind` field set to `gitHubUser` and an extra `name` string with the user organization name, e.g. `CodeSandwich` or `drips-network`. Anybody can request the oracle to generate claims for any profile. The oracle checks all profile social account links and parses them as [ownership URLs](#ownership-urls). Social account links are set up in the profile's general settings. The ownership URLs may be removed after the oracle signs ownership claims, it won't affect the ownership. The returned `sourceId` is `7`, `name` is the copy of the `name` passed as the argument and `timestamp` is the timestamp of when the lookup was made.

# GitLab

## Claiming a repository

See [Claiming a repository](#claiming-a-repository). The `source` argument must have `kind` field set to `gitLab` and the returned `sourceId` is `1`.

## Claiming a user

The `source` argument must have `kind` field set to `gitLabUser` and an extra `token` string with a personal access token. The token is created on the access settings page of the user. The oracle parses the token name as a single [ownership URL](#ownership-urls). The token must include the `read_user` scope and must be valid during the oracle lookup, but its description doesn't matter, it's ignored. The user may remove the access token after the oracle signs ownership claims, it won't affect the ownership. The returned `sourceId` is `8`, same as for GitLab groups, `name` is the canonical name of the user and `timestamp` is the timestamp of when the personal access token was created.

## Claiming a group

The `source` argument must have `kind` field set to `gitLabGroup` and an extra `name` string with the group name, e.g. `drips` or `drips/protocol_sub_group/'evm_people`. Anybody can request the oracle to generate claims for any group. The oracle checks all group badges and parses them as [ownership URLs](#ownership-urls). Badges are set up in the group's general settings, they are publicly available but not displayed in the default GitLab UI. Badge names and image URLs don't matter, they are ignored. The user may remove the ownership URLs after the oracle signs ownership claims, it won't affect the ownership. The returned `sourceId` is `8`, same as for GitLab users, `name` is the copy of the `name` passed as the argument and `timestamp` is the timestamp of when the lookup was made.

# HuggingFace

## Claiming a model

The repository must be public, it must contain `README.md` file in its root directory with the ownership information accessible when checking out the tip commit of the default branch. Anybody can request the oracle to generate claims for any repository. If `README.md` is nonexistent, removed, has YAML header malformed or the repository is non-public or nonexistent, ownerships for all chains are considered to be the zero address. The oracle looks up the `README.md` file, parses its metadata YAML header and looks up the string under `funding` -> `drips` -> chain name -> `ownedBy` and then parses it as an EIP-55 checksummed address. If the ownership claim can't be found under the requested chain's `ownedBy` field or if it's malformed (e.g. invalidly checksummed), the claimed address is considered to be the zero address. The YAML header can contain any data, the oracle will ignore all the unexpected fields. When `README.md` is modified, lookups will start yielding the new ownerships.

A minimal example of `README.md`:
```yaml
---
funding:
  drips:
    ethereum:
      ownedBy: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    optimism:
      ownedBy: "0x220866B1A2219f40e72f5c628B65D54268cA3A9D"
---
Hello markdown!
```

The `source` argument must have `kind` field set to `huggingFace` and an extra `name` string with the canonical repository name in format `<owner>/<repository>`, e.g. `deepseek-ai/DeepSeek-R1`. The returned `sourceId` is `5`, `name` is the copy of the `name` passed as the argument and `timestamp` is the timestamp of when the lookup was made.

## Claiming a dataset

See [Claiming a model](#claiming-a-model). The `source` argument must have `kind` field set to `huggingFaceDataset` and the returned `sourceId` is `6`.

# Claiming a user

The `source` argument must have `kind` field set to `huggingFaceUser` and an extra `token` string with an access token. The token is created on the access tokens settings page of the user. The oracle parses the token name as a single [ownership URL](#ownership-urls). The token may have any permissions, a fine-grained token with no permissions is sufficient. The token must be valid during the oracle lookup. The user may remove the access token after the oracle signs ownership claims, it won't affect the ownership. The returned `sourceId` is `11`, `name` is the canonical name of the user and `timestamp` is the timestamp of when the access token was created.

# Codeberg

## Claiming a repository

See [Claiming a repository](#claiming-a-repository). The `source` argument must have `kind` field set to `codeberg` and the returned `sourceId` is `9`.

## Claiming a user

The `source` argument must have `kind` field set to `codebergUser` and an extra `token` string with an access token. The token is created on the applications settings page of the user. The oracle parses the token name as a single [ownership URL](#ownership-urls). The token must include at least the `user` reading scope. The token must be valid during the oracle lookup. The user may remove the access token after the oracle signs ownership claims, it won't affect the ownership. The returned `sourceId` is `10`, `name` is the canonical name of the user and `timestamp` is the timestamp of when the lookup was made.

# Radicle

## Claiming a repository

See [Claiming a repository](#claiming-a-repository). The `source` argument must have `kind` field set to `radicle` and the returned `sourceId` is `12`. The canonical repository name is the RID without the `rid:` prefix, e.g. `z3gqcJUoA1n9HaHKufZs5FCSGazv5`. The oracle uses the `iris.radicle.xyz` node.

# ORCID

## Claiming a user

The `source` argument must have `kind` field set to `orcid` and an extra `name` string with the user ORCID, e.g. `0123-4567-8901-234X`. Anybody can request the oracle to generate claims for any ORCID. The oracle checks all user profile website and social links and parses them as [ownership URLs](#ownership-urls). Links are set up on the user account edit page. Link names don't matter, they are ignored. The user may remove the ownership URLs after the oracle signs ownership claims, it won't affect the ownership. The returned `sourceId` is `2`, `name` is the copy of the `name` passed as the argument and `timestamp` is the timestamp of when the lookup was made.

## Claiming a user in the ORCID sandbox environment

See [Claiming a user](#claiming-a-user-3). This is a purely test source for the developers, no end users should be using it and sandbox ORCID accounts should never be receiving any real funds. The `source` argument must have `kind` field set to `orcidSandbox` and the returned `sourceId` is `4`.

# Website

## Claiming a website

The `source` argument must have `kind` field set to `website` and an extra `name` string with the website URL. The URL should only consist of the host and an optional path e.g. `example.com` or `example.com/me/my_page`. It should not contain the scheme, the protocol, the port, query parameters or the fragment. Anybody can request the oracle to generate claims for any website. The oracle will query the URL `https://<name>/FUNDING.json` and parse the received [FUNDING.json](#fundingjson) file if the HTTP status code is a success code 2XX. If the status code is 401, 403 or 404, or `FUNDING.json` is malformed, it's considered missing and ownerships for all chains are considered to be the zero address. Any other status code is considered a temporary server malfunction and results in no ownership claims signed. The returned `sourceId` is `3`, `name` is the copy of the `name` passed as the argument and `timestamp` is the timestamp of when the lookup was made.
