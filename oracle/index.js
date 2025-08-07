// SPDX-License-Identifier: GPL-3.0-only

import * as ethers from "ethers";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { mkdtempDisposable } from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { fileURLToPath } from "node:url";
import { createAuthManager, storagePlugins } from "@lit-protocol/auth";
import { createLitClient } from "@lit-protocol/lit-client";
import { getIpfsId } from "@lit-protocol/lit-client/ipfs";
import * as litNetworks from "@lit-protocol/networks";
import { privateKeyToAccount } from "viem/accounts";

async function deposit() {
  const amountInEth = process.argv[3];
  assert(amountInEth, "Expected args: <amount>");

  const litClient = await createLitClientCustom();
  const account = getPrivateKeyAccount();
  const paymentManager = await litClient.getPaymentManager({ account });
  const result = await paymentManager.deposit({ amountInEth });
  litClient.disconnect();

  console.log("Deposited in TX", result.hash);
}

async function getDeployment() {
  const litActionCode = getLitActionCode();
  const litActionIpfsCid = await getIpfsId(litActionCode);
  let outputPath = process.argv[3];
  if (outputPath) {
    writeFileSync(outputPath, litActionCode);
    console.log("The full Lit Action code saved to ", outputPath);
  } else {
    console.log("The full Lit Action code output path argument not provided, not saving.");
  }
  console.log("It's recommended to store the full Lit Action code on IPFS.");
  console.log("The Lit Action IPFS hash:", litActionIpfsCid);
  console.log("The Lit Action signing addresses:");
  for (const network of Object.values(networks)) {
    try {
      const litClient = await createLitClient({ network });
      const litActionAddress = await getLitActionAddress(litClient, litActionCode);
      litClient.disconnect();
      console.log(`  - For ${network.getNetworkName()}: ${litActionAddress}`);
    } catch (error) {
      console.log(`  - For ${network.getNetworkName()} got error: ${error}`);
    }
  }
}

async function queryByName() {
  let kind = process.argv[3];
  let name = process.argv[4];
  let chains = process.argv.slice(5);
  assert(chains.length, "Expected args: <name> [chains]");
  await queryBySource({ kind, name }, chains);
}

async function queryByToken() {
  let kind = process.argv[3];
  let token = process.argv[4];
  let chains = process.argv.slice(5);
  assert(chains.length, "Expected args: <token> [chains]");
  await queryBySource({ kind, token }, chains);
}

async function queryBySource(source, chains) {
  const account = getPrivateKeyAccount();
  const litActionCode = getLitActionCode();
  const litActionIpfsCid = await getIpfsId(litActionCode);
  const litClient = await createLitClientCustom();
  console.log("Connected to network:", litClient.networkName);
  const paymentManager = await litClient.getPaymentManager({ account });
  console.log("Payments will be made from wallet:", account.address);
  console.log(
    "The wallet has deposited balance:",
    (await paymentManager.getBalance({ userAddress: account.address })).availableBalance,
  );
  const litActionAddress = await getLitActionAddress(litClient, litActionCode);

  await using storageDir = await mkdtempDisposable(path.join(os.tmpdir(), "lit-storage-"));
  const authManager = createAuthManager({
    storage: storagePlugins.localStorageNode({
      appName: "oracle",
      networkName: "network",
      storagePath: storageDir.path,
    }),
  });
  const authContext = await authManager.createEoaAuthContext({
    authConfig: {
      resources: [["lit-action-execution", litActionIpfsCid]],
      expiration: new Date(Date.now() + 1000 * 60 * 5).toISOString(),
      statement: "",
    },
    config: { account },
    litClient,
  });

  const {
    logs,
    response: responseRaw,
    signatures,
  } = await litClient.executeJs({
    authContext,
    code: litActionCode,
    responseStrategy: { strategy: "mostCommon" },
    jsParams: { source, chains },
  });
  const response = typeof responseRaw === "string" ? JSON.parse(responseRaw) : responseRaw;

  litClient.disconnect();

  console.log("Logs:", logs.replaceAll(/(.*)\n/g, "\n> $1"));
  console.log("Oracle address:", litActionAddress);
  console.log("Source ID:", response.sourceId);
  console.log("Name:", response.name || "<failed to obtain>");
  let name;
  try {
    name = response.name ? ethers.toUtf8String(response.name) : "<failed to obtain>";
  } catch (error) {
    name = "<not a valid UTF-8 sequence>";
  }
  console.log("Name as UTF-8:", name);
  console.log("Timestamp:", response.timestamp || "<failed to obtain>");
  for (const chain in response.owners) {
    console.log(`Chain ${chain}:`);
    console.log("    Owner:", response.owners[chain]);
    const signature = ethers.Signature.from(
      signatures[chain].signature + "0" + signatures[chain].recoveryId,
    );
    console.log("    R:", signature.r);
    console.log("    VS:", signature.yParityAndS);

    const recoveredAddress = ethers.verifyTypedData(
      { name: "DripsOwnership", version: "1" },
      {
        DripsOwnership: [
          { name: "chain", type: "bytes32" },
          { name: "sourceId", type: "uint8" },
          { name: "name", type: "bytes" },
          { name: "owner", type: "address" },
          { name: "timestamp", type: "uint32" },
        ],
      },
      {
        chain: ethers.encodeBytes32String(chain),
        sourceId: response.sourceId,
        name: response.name,
        owner: response.owners[chain],
        timestamp: response.timestamp,
      },
      signature,
    );
    assert(recoveredAddress === litActionAddress, "Invalid signature");
  }
}

const networks = {
  dev: litNetworks.nagaDev,
  test: litNetworks.nagaTest,
  naga: litNetworks.nagaMainnet,
};

function getNetwork() {
  const envName = "NETWORK";
  const name = process.env[envName];
  const network = name ? networks[name] : networks.dev;
  assert(network, `Environment variable '${envName}' set to an invalid value '${name}'`);
  return network;
}

async function createLitClientCustom() {
  return await createLitClient({ network: getNetwork() });
}

function getPrivateKeyAccount() {
  const envName = "ETHEREUM_PRIVATE_KEY";
  const privateKey = process.env[envName];
  assert(privateKey, `Environment variable '${envName}' not set`);
  return privateKeyToAccount(privateKey);
}

function getLitActionCode() {
  return readCode("./node_modules/js-yaml/dist/js-yaml.min.js") + readCode("./litAction.js");
}

function readCode(path) {
  return readFileSync(fileURLToPath(import.meta.resolve(path)), "utf-8");
}

async function getLitActionAddress(litClient, code) {
  const ipfsCid = await getIpfsId(code);
  const keyId = ethers.keccak256(ethers.toUtf8Bytes("lit_action_" + ipfsCid));
  const publicKey = await litClient.utils.getDerivedKeyId(keyId);
  return ethers.computeAddress(publicKey);
}

await {
  deposit,
  getDeployment,
  queryByName,
  queryByToken,
}[process.argv[2]]();
