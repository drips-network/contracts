import { LitNodeClient } from "@lit-protocol/lit-node-client";
import { AUTH_METHOD_SCOPE, AUTH_METHOD_TYPE, LIT_NETWORK, LIT_RPC, LIT_ABILITY } from "@lit-protocol/constants";
import {
  createSiweMessageWithRecaps,
  generateAuthSig,
  LitActionResource,
} from "@lit-protocol/auth-helpers";
import { LitContracts } from "@lit-protocol/contracts-sdk";
import * as ethers from "ethers";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const litNetwork = LIT_NETWORK.DatilTest;

export async function query() {
  let sourceId;
  let name;
  let chains;
  try {
    sourceId = parseInt(process.argv[1]);
    assert(sourceId >= 0 && sourceId <= 127); // A correctly parsed source ID integer
    name = process.argv[2];
    assert(name); // A non-empty string
    chains = process.argv.slice(3);
    assert(chains.length); // A non-empty array
  } catch (error) {
    throw new Error("Expected args: [sourceId] [name] [list of chains]");
  }

  const capacityTokenId = process.env.CAPACITY_CREDIT_TOKEN_ID;
  assert(capacityTokenId, "CAPACITY_CREDIT_TOKEN_ID environment variable not set");
  let publicKey = process.env.PKP_PUBLIC_KEY || await mintPkp();
  const litWallet = createLitWallet();

  const litNodeClient = new LitNodeClient({
    litNetwork,
    debug: false,
  });

  const { capacityDelegationAuthSig } =
    await litNodeClient.createCapacityDelegationAuthSig({
      dAppOwnerWallet: litWallet,
      capacityTokenId, // default is any active capacity credit token
      delegateeAddresses: [litWallet.address],
      uses: "1", // default is unlimited
      expiration: new Date(Date.now() + 1000 * 60 * 10).toISOString(), // 10 minutes, default is 7 days
    });

  const sessionSigs = await litNodeClient.getSessionSigs({
      chain: "ethereum",
      capabilityAuthSigs: [capacityDelegationAuthSig],
      expiration: new Date(Date.now() + 1000 * 60 * 10).toISOString(), // 10 minutes
      resourceAbilityRequests: [
        {
          resource: new LitActionResource(await litActionIpfsId()),
          ability: LIT_ABILITY.LitActionExecution,
        },
      ],
      authNeededCallback: async ({
        resourceAbilityRequests,
        expiration,
        uri,
      }) => {
        const toSign = await createSiweMessageWithRecaps({
          uri: uri!,
          expiration: expiration!,
          resources: resourceAbilityRequests!,
          walletAddress: litWallet.address,
          nonce: await litNodeClient.getLatestBlockhash(),
          litNodeClient,
        });

        return await generateAuthSig({
          signer: litWallet,
          toSign,
        });
      },
    });

    const response = await litNodeClient.executeJs({
      sessionSigs,
      code: litAction,
      responseStrategy: { strategy: 'mostCommon' },
      jsParams: { publicKey, sourceId, name, chains },
    });

    console.log("Oracle address:", ethers.utils.computeAddress(publicKey));
    console.log("Source ID:", sourceId);
    console.log("Name:", name);
    console.log("Timestamp:", response.response.timestamp);
    for(const chain of chains) {
      console.log(`Chain ${chain}:`);
      console.log("    Owner:", response.response.owners[chain]);
      const signature = ethers.utils.splitSignature(response.signatures[chain].signature);
      console.log("    R:", signature.r);
      console.log("    VS:", signature.yParityAndS);
    }

    process.exit();
}

export async function mintPkp(): string {
  const litContracts = new LitContracts({signer: createLitWallet(), network: litNetwork});
  await litContracts.connect();

  console.log("Minting PKP using NFT contract", litContracts.pkpNftContract.read.address);
  const ipfsId = await litActionIpfsId();
  const receipt = await litContracts.mintWithCustomAuth({
    authMethodType: AUTH_METHOD_TYPE.LitAction,
    authMethodId: ethers.utils.base58.decode(ipfsId),
    scopes: [AUTH_METHOD_SCOPE.SignAnything]
  });
  const publicKey = receipt.pkp.publicKey.replace(/^(0x)?/, "0x")
  console.log("PKP public key", publicKey);
  console.log("PKP address", receipt.pkp.ethAddress);
  console.log("PKP authorized action IPFS ID", ipfsId);
  return publicKey;
}

const litAction = readFileSync(fileURLToPath(import.meta.resolve("./litAction.ts")), "utf-8");

async function litActionIpfsId(): string {
  return new LitNodeClient({litNetwork, debug: false}).getIpfsId({str: litAction});
}

function createLitWallet(): ethers.Wallet {
  const privateKey = process.env.ETHEREUM_PRIVATE_KEY;
  assert(privateKey, "ETHEREUM_PRIVATE_KEY environment variable not set");
  return new ethers.Wallet(
      privateKey,
      new ethers.providers.JsonRpcProvider(LIT_RPC.CHRONICLE_YELLOWSTONE)
  );
}
