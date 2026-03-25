// SPDX-License-Identifier: GPL-3.0-only

async function main({ chains, source }) {
  verifyChains(chains);
  const { sourceId, name, timestamp, claims, revokeUnclaimed } = await getClaims(source);
  const owners = claimsToOwners(claims, revokeUnclaimed, chains);
  const wallet = new ethers.Wallet(await LitActions.getLitActionPrivateKey());
  const signedOwners = await signOwners(wallet, owners, sourceId, name, timestamp);
  return { sourceId, name, timestamp, chains: signedOwners, oracleAddress: wallet.address };
}

function verifyChains(chains) {
  if (!Array.isArray(chains)) {
    throw Error("Argument 'chains' must be an array");
  }
  for (chain of chains) {
    if (!chain || typeof chain !== "string") {
      throw Error("Argument 'chains' must only contain non-empty strings");
    }
    if (chain.endsWith("\0")) {
      throw Error(`Argument 'chains' contain value ending with the zero byte '${chain}'`);
    }
    if (chains.indexOf(chain) !== chains.lastIndexOf(chain)) {
      throw Error(`Argument 'chains' contains duplicate value '${chain}'`);
    }
    try {
      ethers.utils.formatBytes32String(chain);
    } catch (error) {
      throw Error(`Argument 'chains' contains too long value '${chain}'`);
    }
  }
}

async function getClaims(source) {
  const kind = getSourceValue(source, "kind");
  let sourceId, result;
  if (kind === "gitHub") {
    sourceId = 0;
    result = await tryGetJsonClaims("raw.githubusercontent.com/{name}/HEAD", getName(source));
  } else if (kind === "gitLab") {
    sourceId = 1;
    result = await tryGetJsonClaims("gitlab.com/{name}/-/raw/HEAD", getName(source));
  } else if (kind === "orcid") {
    sourceId = 2;
    result = await tryGetOrcidClaims("", getName(source));
  } else if (kind === "website") {
    sourceId = 3;
    result = await tryGetJsonClaims("{name}", getName(source));
  } else if (kind === "orcidSandbox") {
    sourceId = 4;
    result = await tryGetOrcidClaims("sandbox.", getName(source));
  } else if (kind === "huggingFace") {
    sourceId = 5;
    result = await tryGetHuggingFaceClaims("", getName(source));
  } else if (kind === "huggingFaceDataset") {
    sourceId = 6;
    result = await tryGetHuggingFaceClaims("datasets/", getName(source));
  } else if (kind === "gitHubUser") {
    sourceId = 7;
    result = await tryGetGitHubUserClaims(getName(source));
  } else if (kind === "gitLabUser") {
    sourceId = 8;
    result = await tryGetGitLabUserClaims(getToken(source));
  } else if (kind === "gitLabGroup") {
    sourceId = 8;
    result = await tryGetGitLabGroupClaims(getName(source));
  } else if (kind === "codeberg") {
    sourceId = 9;
    result = await tryGetJsonClaims("codeberg.org/{name}/raw", getName(source));
  } else if (kind === "codebergUser") {
    sourceId = 10;
    result = await tryGetCodebergUserClaims(getToken(source));
  } else if (kind === "huggingFaceUser") {
    sourceId = 11;
    result = await tryGetHuggingFaceUserClaims(getToken(source));
  } else if (kind === "radicle") {
    sourceId = 12;
    result = await tryGetRadicleClaims(getName(source));
  } else {
    throw Error(`Argument 'source' has an unknown 'kind' value '${kind}'`);
  }

  const name = result?.name ? ethers.utils.hexlify(ethers.utils.toUtf8Bytes(result.name)) : null;
  if (name?.endsWith("00")) throw Error("The account name ends with the zero byte");
  const timestamp = result?.timestamp || null;
  const claims = name && timestamp && result?.claims ? result.claims : [];
  const revokeUnclaimed = Boolean(result?.revokeUnclaimed);
  return { sourceId, name, timestamp, claims, revokeUnclaimed };
}

function getName(source) {
  return getSourceValue(source, "name");
}

function getToken(source) {
  return getSourceValue(source, "token");
}

function getSourceValue(source, key) {
  const value = source?.[key];
  if (typeof value !== "string") throw Error(`Argument 'source' must contain the '${key}' string`);
  return value;
}

function claimsToOwners(claims, revokeUnclaimed, chains) {
  const unclaimedMessage = revokeUnclaimed ? "revoking ownership" : "skipping";
  const owners = {};
  for (const chain of chains) {
    let owner = revokeUnclaimed ? ethers.constants.AddressZero : undefined;
    let message;
    const chainClaims = claims.filter((claim) => claim.chain === chain);
    if (chainClaims.length === 1) {
      try {
        owner = ethers.utils.getAddress(chainClaims[0].ownedBy);
        message = `found ownership claim ${owner}`;
      } catch (error) {
        message = `failed to parse the claim address, ${unclaimedMessage}`;
      }
    } else {
      message = `found ${chainClaims.length} claims, ${unclaimedMessage}`;
    }
    console.log(`For chain '${chain}' ${message}`);
    if (owner) {
      owners[chain] = owner;
    }
  }
  return owners;
}

async function signOwners(wallet, owners, sourceId, name, timestamp) {
  const chains = {};
  for (const [chain, owner] of Object.entries(owners)) {
    const signature = await wallet._signTypedData(
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
        chain: ethers.utils.formatBytes32String(chain),
        sourceId,
        name,
        owner,
        timestamp,
      },
    );
    const { r, yParityAndS: vs } = ethers.utils.splitSignature(signature);
    chains[chain] = { owner, r, vs };
  }
  return chains;
}

async function tryGetJsonClaims(url, name) {
  const timestamp = await getNowTimestamp();
  let claims;
  const result = await tryFetchJson(url.replace("{name}", name) + "/FUNDING.json");
  try {
    if (result.error) throw result.error;
    claims = fundingDocToClaims(result.json);
  } catch (error) {
    console.log(error);
  }
  return { name, timestamp, claims, revokeUnclaimed: result.isMeaningful };
}

async function tryGetOrcidClaims(subdomain, name) {
  const timestamp = await getNowTimestamp();
  try {
    const result = await tryFetchJson(`pub.${subdomain}orcid.org/v3.0/${name}/researcher-urls`);
    if (result.error) throw result.error;
    const urls = result.json?.["researcher-url"];
    if (!Array.isArray(urls)) throw Error("Response missing the `researcher-url` array");
    const claims = urls.flatMap((url) => tryUrlToClaims(url?.url?.value));
    return { name, timestamp, claims };
  } catch (error) {
    console.log(error);
  }
}

async function tryGetGitHubUserClaims(name) {
  const timestamp = await getNowTimestamp();
  try {
    const result = await tryFetchJson(`api.github.com/users/${name}/social_accounts`, {
      headers: { "X-GitHub-Api-Version": "2022-11-28" },
    });
    if (result.error) throw result.error;
    if (!Array.isArray(result.json)) throw Error("Response not an array");
    const claims = result.json.flatMap((account) => tryUrlToClaims(account.url));
    return { name, timestamp, claims };
  } catch (error) {
    console.log(error);
  }
}

async function tryGetGitLabUserClaims(token) {
  try {
    const options = { headers: { "PRIVATE-TOKEN": token } };

    const tokenResult = await tryFetchJson(
      "gitlab.com/api/v4/personal_access_tokens/self",
      options,
    );
    if (tokenResult.error) throw tokenResult.error;
    const json = tokenResult.json;
    if (json?.active !== true) throw Error("Token inactive");
    const timestamp = Math.trunc(new Date(json?.created_at) / 1000);
    if (!timestamp) throw Error("Response missing the 'created_at' date");
    const claims = urlToClaims(json?.name);

    const userResult = await tryFetchJson("gitlab.com/api/v4/user", options);
    if (userResult.error) throw userResult.error;
    const name = userResult.json?.username;
    if (typeof name !== "string") throw Error("Response missing the `username` string");

    return { name, timestamp, claims };
  } catch (error) {
    console.log(error);
  }
}

async function tryGetGitLabGroupClaims(name) {
  const timestamp = await getNowTimestamp();
  try {
    const nameUri = name.replaceAll("/", "%2F");
    const result = await tryFetchJson(`gitlab.com/api/v4/groups/${nameUri}/badges`);
    if (result.error) throw result.error;
    if (!Array.isArray(result.json)) throw Error("Response not an array");
    const claims = result.json.flatMap((badge) => tryUrlToClaims(badge?.link_url));
    return { name, timestamp, claims };
  } catch (error) {
    console.log(error);
  }
}

async function tryGetCodebergUserClaims(token) {
  const timestamp = await getNowTimestamp();
  try {
    const url = "codeberg.org/api/v1";
    const options = { headers: { Authorization: "token " + token } };

    const userResult = await tryFetchJson(`${url}/user`, options);
    if (userResult.error) throw userResult.error;
    const name = userResult.json?.login;
    if (typeof name !== "string") throw Error("Response missing the `login` string");

    const tokensResult = await tryFetchJson(`${url}/users/${name}/tokens`, options);
    if (tokensResult.error) throw tokensResult.error;
    const tokens = tokensResult.json;
    if (!Array.isArray(tokens)) throw Error("Response not an array");
    const tokenInfo = tokens.find((tokenInfo) => token.endsWith(tokenInfo?.token_last_eight));
    const claims = urlToClaims(tokenInfo.name);

    return { name, timestamp, claims };
  } catch (error) {
    console.log(error);
  }
}

async function tryGetHuggingFaceUserClaims(token) {
  try {
    const options = { headers: { Authorization: "Bearer " + token } };

    const result = await tryFetchJson("huggingface.co/api/whoami-v2", options);
    if (result.error) throw result.error;
    const json = result.json;

    if (json?.type !== "user") throw Error("The token is not a user access token");
    if (json?.auth?.type !== "access_token") throw Error("The token is not an access token");

    const name = json?.name;
    if (typeof name !== "string") throw Error("Response missing the `name` string");

    const timestamp = Math.trunc(new Date(json?.auth?.accessToken?.createdAt) / 1000);
    if (!timestamp) throw Error("Response missing the 'createdAt' date");

    const displayName = json?.auth?.accessToken?.displayName;
    if (!displayName) throw Error("Reponse missing the 'displayName' string");
    const claims = urlToClaims(displayName);

    return { name, timestamp, claims };
  } catch (error) {
    console.log(error);
  }
}

async function tryGetHuggingFaceClaims(subPath, name) {
  const timestamp = await getNowTimestamp();
  let claims;
  const result = await tryFetchText(`huggingface.co/${subPath}${name}/resolve/HEAD/README.md`);
  try {
    if (result.error) throw result.error;
    const yaml = tryParseYaml(result.text);
    claims = fundingDocToClaims(yaml?.funding);
  } catch (error) {
    console.log(error);
  }
  return { name, timestamp, claims, revokeUnclaimed: result.isMeaningful };
}

function tryParseYaml(yaml) {
  try {
    return jsyaml.load(yaml);
  } catch (error) {
    // Removes the last yaml document from the string.
    // If there's only 1 document, leaves an empty string which then parses as an empty object.
    return tryParseYaml(yaml.match(/(.*)(---|^)/s)[1]);
  }
}

async function tryGetRadicleClaims(name) {
  const timestamp = await getNowTimestamp();
  let claims;
  let revokeUnclaimed;
  try {
    const url = "iris.radicle.xyz/api/v1/repos/rad:" + name;
    const resultMetadata = await tryFetchJson(url);
    revokeUnclaimed = resultMetadata.isMeaningful;
    if (resultMetadata.error) throw resultMetadata.error;
    const head = resultMetadata.json?.payloads?.["xyz.radicle.project"]?.meta?.head;
    if (typeof head != "string") throw Error("Response missing the `head` string");

    const result = await tryFetchJson(`${url}/blob/${head}/FUNDING.json`);
    revokeUnclaimed = result.isMeaningful;
    if (result.error) throw result.error;
    const content = result.json?.content;
    if (typeof content != "string") throw Error("Response missing the `content` string");
    claims = fundingDocToClaims(JSON.parse(content));
  } catch (error) {
    console.log(error);
  }
  return { name, timestamp, claims, revokeUnclaimed };
}

async function getNowTimestamp() {
  return Math.floor(Date.now() / 1000);
}

function fundingDocToClaims(doc) {
  const claims = doc?.drips;
  if (!claims || typeof claims !== "object")
    throw Error("No ownership claims found in the document");
  return Object.entries(claims).map(([chain, claim]) => ({ chain, ownedBy: claim?.ownedBy }));
}

function tryUrlToClaims(urlString) {
  try {
    return urlToClaims(urlString);
  } catch (error) {
    return [];
  }
}

function urlToClaims(urlString) {
  if (!URL.canParse(urlString)) throw Error("Claims URL malformed");
  const url = new URL(urlString);
  const urlRoot = "http://0.0.0.0/DRIPS_OWNERSHIP_CLAIM";
  if (url.href !== urlRoot + url.search) throw Error(`Claims URL doesn't point at '${urlRoot}'`);
  return new URLSearchParams(url.searchParams)
    .entries()
    .map(([chain, ownedBy]) => ({ chain, ownedBy }))
    .toArray();
}

async function tryFetchJson(url, options = {}) {
  options.headers = { ...options.headers, "Content-Type": "application/json" };
  const result = await tryFetchText(url, options);
  if (!result.text) return result;
  try {
    result.json = JSON.parse(result.text);
  } catch (error) {
    result.error = error;
  }
  return result;
}

async function tryFetchText(url, options = {}) {
  const result = {};
  options.signal = AbortSignal.timeout(30_000);
  const fullUrl = "https://" + url;
  console.log("Fetching from", fullUrl);
  for (let retries = 2; retries >= 0; retries--) {
    try {
      const response = await fetch(fullUrl, options);
      // Ensure that the entire body has been transferred and no network failure can occur.
      await response.clone().arrayBuffer();
      // The response correctly describes a resource, even if it's nonpublic or nonexistent.
      result.isMeaningful = response.ok || [401, 403, 404].includes(response.status);
      if (result.isMeaningful) retries = 0;
      if (!response.ok) throw Error("HTTP status " + response.status);
      result.text = await response.text();
    } catch (error) {
      if (retries > 0) {
        console.log(error);
        console.log("Retrying");
      } else {
        result.error = error;
      }
    }
  }
  return result;
}
