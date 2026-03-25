// SPDX-License-Identifier: GPL-3.0-only

import * as ethers from "ethers";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

async function getDeployment() {
  const litActionCode = getLitActionCode();
  let outputPath = process.argv[3];
  if (outputPath) {
    writeFileSync(outputPath, litActionCode);
    console.log("The full Lit Action code saved to ", outputPath);
  } else {
    console.log("The full Lit Action code output path argument not provided, not saving.");
  }
  console.log("It's recommended to store the full Lit Action code on IPFS.");

  const litApi = getLitApi();
  const litActionIpfsCid = await litApi.post("get_lit_action_ipfs_id", litActionCode);
  console.log("The Lit Action IPFS hash:", litActionIpfsCid);
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
  const litApi = getLitApi(getLitApiKey());

  const { logs, response } = await litApi.post("lit_action", {
    code: getLitActionCode(),
    js_params: { source, chains },
  });

  console.log("Logs:", logs.replaceAll(/(.*)\n/g, "\n> $1"));
  console.log("Oracle address:", response.oracleAddress);
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
  for (const [chain, claim] of Object.entries(response.chains)) {
    console.log(`Chain ${chain}:`);
    console.log("    Owner:", claim.owner);
    console.log("    R:", claim.r);
    console.log("    VS:", claim.vs);

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
        owner: claim.owner,
        timestamp: response.timestamp,
      },
      { r: claim.r, yParityAndS: claim.vs },
    );
    assert(recoveredAddress === response.oracleAddress, "Invalid signature");
  }
}

function getLitApiKey() {
  const envName = "LIT_API_KEY";
  const apiKey = process.env[envName];
  assert(apiKey, `Environment variable '${envName}' not set`);
  return apiKey;
}

function getLitApi(apiKey) {
  async function get(urlSuffix, options = {}) {
    if (apiKey) options.headers = { ...options.headers, "X-Api-Key": apiKey };
    const url = "https://api.chipotle.litprotocol.com/core/v1/" + urlSuffix;
    const response = await fetch(url, options);
    if (!response.ok) throw Error(`HTTP status ${response.status}: ${await response.json()}`);
    return await response.json();
  }

  async function post(urlSuffix, json) {
    return await this.get(urlSuffix, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(json),
    });
  }

  return { get, post };
}

function getLitActionCode() {
  const readCode = (path) => readFileSync(fileURLToPath(import.meta.resolve(path)), "utf-8");
  return readCode("./node_modules/js-yaml/dist/js-yaml.min.js") + readCode("./litAction.js");
}

await {
  getDeployment,
  queryByName,
  queryByToken,
}[process.argv[2]]();
