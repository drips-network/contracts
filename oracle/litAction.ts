const gitHub = 0;
const gitLab = 1;
// const orcid = 2;
const website = 3;

async function main() {
    const timestamps = await Lit.Actions.broadcastAndCollect({
        name: "timestamp",
        value: Math.trunc(Date.now() / 1000).toString()
    });
    const timestamp = timestamps.map(Number).sort().at(timestamps.length / 2);

    let url;
    if(sourceId === gitHub) url = `https://raw.githubusercontent.com/${name}/HEAD/FUNDING.json`;
    else if(sourceId === gitLab) url = `https://gitlab.com/${name}/-/raw/HEAD/FUNDING.json`;
    else if(sourceId === website) url = `https://${name}/FUNDING.json`;
    else throw Error(`Unknown source ID ${sourceId}`);

    const response = await fetch(url);
    // Ensure that the entire body has been transferred and no network failure can occur.
    await response.clone().arrayBuffer();
    // Got a valid response, from now on any failure will be considered an ownership revocation.
    if(!response.ok && response.status !== 403 && response.status !== 404) {
        throw Error(`Failed to fetch FUNDING.json with HTTP status ${response.status}`);
    }
    const json = await response.json().catch(() => {});
    const owners = {};

    for(const chain of chains) {
        let owner = ethers.constants.AddressZero;
        try {
            owner = ethers.utils.getAddress(json.drips[chain].ownedBy);
        } catch (error) {}
        owners[chain] = owner;
        const payload = ethers.utils._TypedDataEncoder.hash(
            {name: "DripsOwnership", version: "1"},
            { DripsOwnership: [
                { name: "chain", type: "bytes32"},
                { name: "sourceId", type: "uint8"},
                { name: "name", type: "bytes"},
                { name: "owner", type: "address"},
                { name: "timestamp", type: "uint32"}
            ]},
            {
                chain: ethers.utils.formatBytes32String(chain),
                sourceId,
                name: ethers.utils.toUtf8Bytes(name),
                owner,
                timestamp
            }
          );
        await Lit.Actions.signEcdsa({toSign: ethers.utils.arrayify(payload), publicKey, sigName: chain });
    }

    Lit.Actions.setResponse({response: JSON.stringify({timestamp, owners})});
}

main();
