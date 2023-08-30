// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Caller} from "src/Caller.sol";
import {AddressDriver} from "src/AddressDriver.sol";
import {
    AccountMetadata,
    Drips,
    IERC20,
    StreamConfigImpl,
    StreamsHistory,
    StreamReceiver,
    SplitsReceiver
} from "src/Drips.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";
import {Test} from "forge-std/Test.sol";

// Generated with `cast interface 0x31c8eacbffdd875c74b94b077895bd78cf1e64a3`
interface RadicleToken {
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event DelegateChanged(
        address indexed delegator, address indexed fromDelegate, address indexed toDelegate
    );
    event DelegateVotesChanged(
        address indexed delegate, uint256 previousBalance, uint256 newBalance
    );
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function DECIMALS() external view returns (uint8);
    function DELEGATION_TYPEHASH() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function DOMAIN_TYPEHASH() external view returns (bytes32);
    function NAME() external view returns (string memory);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function SYMBOL() external view returns (string memory);
    function allowance(address account, address spender) external view returns (uint256);
    function approve(address spender, uint256 rawAmount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function burnFrom(address account, uint256 rawAmount) external;
    function checkpoints(address, uint32) external view returns (uint32 fromBlock, uint96 votes);
    function decimals() external pure returns (uint8);
    function delegate(address delegatee) external;
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function delegates(address) external view returns (address);
    function getCurrentVotes(address account) external view returns (uint96);
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);
    function name() external pure returns (string memory);
    function nonces(address) external view returns (uint256);
    function numCheckpoints(address) external view returns (uint32);
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    function symbol() external pure returns (string memory);
    function totalSupply() external view returns (uint256);
    function transfer(address dst, uint256 rawAmount) external returns (bool);
    function transferFrom(address src, address dst, uint256 rawAmount) external returns (bool);
}

// Generated with `cast interface 0x690e775361AD66D1c4A25d89da9fCd639F5198eD`
interface Governor {
    event ProposalCanceled(uint256 id);
    event ProposalCreated(
        uint256 id,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );
    event ProposalExecuted(uint256 id);
    event ProposalQueued(uint256 id, uint256 eta);
    event VoteCast(address voter, uint256 proposalId, bool support, uint256 votes);

    struct Receipt {
        bool hasVoted;
        bool support;
        uint96 votes;
    }

    function BALLOT_TYPEHASH() external view returns (bytes32);
    function DOMAIN_TYPEHASH() external view returns (bytes32);
    function NAME() external view returns (string memory);
    function __abdicate() external;
    function __acceptAdmin() external;
    function __executeSetTimelockPendingAdmin(address newPendingAdmin, uint256 eta) external;
    function __queueSetTimelockPendingAdmin(address newPendingAdmin, uint256 eta) external;
    function cancel(uint256 proposalId) external;
    function castVote(uint256 proposalId, bool support) external;
    function castVoteBySig(uint256 proposalId, bool support, uint8 v, bytes32 r, bytes32 s)
        external;
    function execute(uint256 proposalId) external payable;
    function getActions(uint256 proposalId)
        external
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        );
    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory);
    function guardian() external view returns (address);
    function latestProposalIds(address) external view returns (uint256);
    function proposalCount() external view returns (uint256);
    function proposalMaxOperations() external pure returns (uint256);
    function proposalThreshold() external pure returns (uint256);
    function proposals(uint256)
        external
        view
        returns (
            address proposer,
            uint256 eta,
            uint256 startBlock,
            uint256 endBlock,
            uint256 forVotes,
            uint256 againstVotes,
            bool canceled,
            bool executed
        );
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);
    function queue(uint256 proposalId) external;
    function quorumVotes() external pure returns (uint256);
    function state(uint256 proposalId) external view returns (uint8);
    function timelock() external view returns (address);
    function token() external view returns (address);
    function votingDelay() external pure returns (uint256);
    function votingPeriod() external pure returns (uint256);
}

interface Timelock {
    event CancelTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event ExecuteTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event NewAdmin(address indexed newAdmin);
    event NewDelay(uint256 indexed newDelay);
    event NewPendingAdmin(address indexed newPendingAdmin);
    event QueueTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );

    function GRACE_PERIOD() external view returns (uint256);
    function MAXIMUM_DELAY() external view returns (uint256);
    function MINIMUM_DELAY() external view returns (uint256);
    function acceptAdmin() external;
    function admin() external view returns (address);
    function cancelTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) external;
    function delay() external view returns (uint256);
    function executeTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) external payable returns (bytes memory);
    function gracePeriod() external pure returns (uint256);
    function pendingAdmin() external view returns (address);
    function queueTransaction(
        address target,
        uint256 value,
        string memory signature,
        bytes memory data,
        uint256 eta
    ) external returns (bytes32);
    function queuedTransactions(bytes32) external view returns (bool);
    function setDelay(uint256 delay_) external;
    function setPendingAdmin(address pendingAdmin_) external;
}

struct Proposal {
    address[] targets;
    uint256[] values;
    string[] signatures;
    bytes[] calldatas;
    string description;
}

contract ProposalTest is Test {
    AddressDriver public constant ADDRESS_DRIVER =
        AddressDriver(0x1455d9bD6B98f95dd8FEB2b3D60ed825fcef0610);
    Drips public immutable drips = ADDRESS_DRIVER.drips();
    Governor public immutable governor = Governor(TIMELOCK.admin());
    Timelock public constant TIMELOCK = Timelock(0x8dA8f82d2BbDd896822de723F55D6EdF416130ba);
    uint256 public immutable timelockAccountId = ADDRESS_DRIVER.calcAccountId(address(TIMELOCK));
    IERC20 public constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    RadicleToken public constant RAD = RadicleToken(0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3);

    function testProposalRadworksSoftwareDependencies() public {
        assertEq(block.chainid, 1, "Must run on an Ethereum mainnet fork");

        uint256 receiverId = 50330452048867519181028275890986093327647919805766323166158196453514;
        uint128 amtUsdc = 500_000e6;
        uint128 amtRad = 373_134e18;
        uint32 duration = 365 days;
        // This is the calldata that if sent to Governor, proposes this proposal
        bytes memory data =
            hex"da95691a00000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000000007e00000000000000000000000000000000000000000000000000000000000000004000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb480000000000000000000000001455d9bd6b98f95dd8feb2b3d60ed825fcef061000000000000000000000000031c8eacbffdd875c74b94b077895bd78cf1e64a30000000000000000000000001455d9bd6b98f95dd8feb2b3d60ed825fcef0610000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002a000000000000000000000000000000000000000000000000000000000000003200000000000000000000000000000000000000000000000000000000000000044095ea7b30000000000000000000000001455d9bd6b98f95dd8feb2b3d60ed825fcef0610000000000000000000000000000000000000000000000000000000746a528800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000164dde554c6000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb4800000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000746a5288000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008da8f82d2bbdd896822de723f55d6edf416130ba0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000001ddea8d3444e125478cbaa6a678509dfbacef123f4a75bf219812308a0000000000000000000000000000000000000e6b81718c4a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000044095ea7b30000000000000000000000001455d9bd6b98f95dd8feb2b3d60ed825fcef0610000000000000000000000000000000000000000000004f03a279d356fd780000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000164dde554c600000000000000000000000031c8eacbffdd875c74b94b077895bd78cf1e64a300000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000004f03a279d356fd7800000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008da8f82d2bbdd896822de723f55d6edf416130ba0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000001ddea8d3444e125478cbaa6a678509dfbacef123f4a75bf219812308a0000000000000000000000000009c98616770be6c780d3f800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005433136202d2046756e6420526164776f726b7320446570656e64656e6369657320776974682044726970730a0a49662065786563757465642c20746869732070726f706f73616c2077696c6c3a0a0a312e207472616e7366657220353030303030205553444320616e6420333733313334205241442066726f6d2074686520526164776f726b7320547265617375727920616e64206465706f736974207468656d20746f207468652044726970732050726f746f636f6c0a322e2073747265616d207468652061626f76652066756e647320746f2074686520666f6c6c6f77696e672044726970204c697374206f766572206f6e6520796561722068747470733a2f2f7777772e64726970732e6e6574776f726b2f6170702f647269702d6c697374732f3530333330343532303438383637353139313831303238323735383930393836303933333237363437393139383035373636333233313636313538313936343533353134207468617420667572746865722066756e64732074686520736f66747761726520646570656e64656e63696573206f66207468652052616469636c652c20447269707320616e64204772616e7473206f7267732e0a0a232320486f772077617320746869732070726f706f73616c206469736375737365643f0a0a2d2044697363757373696f6e3a2068747470733a2f2f636f6d6d756e6974792e726164776f726b732e6f72672f742f666f726d616c2d7265766965772d7267702d31362d66756e642d726164776f726b732d646570656e64656e636965732d776974682d64726970732f333336370a2d20536e617073686f746520766f74653a2068747470733a2f2f736e617073686f742e6f72672f232f676f762e72616469636c652e6574682f70726f706f73616c2f3078663063356666313336383736636530346230333061343663656662306637623664633233613030383761393933383966353435363764333665303964373636360a0a2323204e6f7465730a0a30784130623836393931633632313862333663316431394434613265394562306345333630366542343820697320746865205553444320636f6e74726163742e0a307833316338454163424646644438373563373462393462303737383935426437384346314536344133206973207468652052414420636f6e74726163742e0a3078386461386638326432626264643839363832326465373233663535643665646634313631333062612069732074686520526164776f726b732054726561737572792e0a3078643044643035333339326462363736443537333137434434666539364663326343663432443062342069732074686520447269707320636f6e747261637420286d61696e20636f6e7472616374206f66207468652044726970732070726f746f636f6c292e0a68747470733a2f2f7777772e64726970732e6e6574776f726b2f6170702f647269702d6c697374732f3530333330343532303438383637353139313831303238323735383930393836303933333237363437393139383035373636333233313636313538313936343533353134206973207468652044726970204c69737420776974682074686520526164776f726b7320616c6c6f636174696f6e2e204974277320636f6e74726f6c6c65642062792074686973204e465420746861742074686520526164776f726b7320547265617375727920686f6c64732068747470733a2f2f65746865727363616e2e696f2f74782f3078623261306333633939653831326563623534353638396261376638333430356337393630633739363431373835373635636432633635393661653563343465630000000000000000000000000000000000000000000000000000000000";

        Proposal memory proposal = Proposal({
            targets: new address[](4),
            values: new uint256[](4), // All values are 0.
            signatures: new string[](4), // All signatures are empty.
            calldatas: new bytes[](4),
            description: unicode"\
16 - Fund Radworks Dependencies with Drips\n\
\n\
If executed, this proposal will:\n\
\n\
1. transfer 500000 USDC and 373134 RAD from the Radworks Treasury and deposit them to the Drips Protocol\n\
2. stream the above funds to the following Drip List over one year https://www.drips.network/app/drip-lists/50330452048867519181028275890986093327647919805766323166158196453514 that further funds the software dependencies of the Radicle, Drips and Grants orgs.\n\
\n\
## How was this proposal discussed?\n\
\n\
- Discussion: https://community.radworks.org/t/formal-review-rgp-16-fund-radworks-dependencies-with-drips/3367\n\
- Snapshote vote: https://snapshot.org/#/gov.radicle.eth/proposal/0xf0c5ff136876ce04b030a46cefb0f7b6dc23a0087a99389f54567d36e09d7666\n\
\n\
## Notes\n\
\n\
0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 is the USDC contract.\n\
0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3 is the RAD contract.\n\
0x8da8f82d2bbdd896822de723f55d6edf416130ba is the Radworks Treasury.\n\
0xd0Dd053392db676D57317CD4fe96Fc2cCf42D0b4 is the Drips contract (main contract of the Drips protocol).\n\
https://www.drips.network/app/drip-lists/50330452048867519181028275890986093327647919805766323166158196453514 is the Drip List with the Radworks allocation. It's controlled by this NFT that the Radworks Treasury holds https://etherscan.io/tx/0xb2a0c3c99e812ecb545689ba7f83405c7960c79641785765cd2c6596ae5c44ec\
"
        });

        // Step 0: approve USDC
        proposal.targets[0] = address(USDC);
        proposal.calldatas[0] = abi.encodeCall(USDC.approve, (address(ADDRESS_DRIVER), amtUsdc));

        // Step 1: start streaming USDC
        proposal.targets[1] = address(ADDRESS_DRIVER);
        StreamReceiver[] memory usdcReceivers = new StreamReceiver[](1);
        usdcReceivers[0] = StreamReceiver({
            accountId: receiverId,
            config: StreamConfigImpl.create({
                streamId_: 0,
                amtPerSec_: amtUsdc * drips.AMT_PER_SEC_MULTIPLIER() / duration,
                start_: 0,
                duration_: 0
            })
        });
        proposal.calldatas[1] = abi.encodeCall(
            ADDRESS_DRIVER.setStreams,
            (USDC, new StreamReceiver[](0), int128(amtUsdc), usdcReceivers, 0, 0, address(TIMELOCK))
        );

        // Step 2: approve RAD
        proposal.targets[2] = address(RAD);
        proposal.calldatas[2] = abi.encodeCall(RAD.approve, (address(ADDRESS_DRIVER), amtRad));

        // Step 3: start streaming USDC
        proposal.targets[3] = address(ADDRESS_DRIVER);
        StreamReceiver[] memory radReceivers = new StreamReceiver[](1);
        radReceivers[0] = StreamReceiver({
            accountId: receiverId,
            config: StreamConfigImpl.create({
                streamId_: 0,
                amtPerSec_: amtRad * drips.AMT_PER_SEC_MULTIPLIER() / duration,
                start_: 0,
                duration_: 0
            })
        });
        proposal.calldatas[3] = abi.encodeCall(
            ADDRESS_DRIVER.setStreams,
            (
                IERC20(address(RAD)),
                new StreamReceiver[](0),
                int128(amtRad),
                radReceivers,
                0,
                0,
                address(TIMELOCK)
            )
        );

        // Verify the proposal calldata
        assertEq(
            data,
            abi.encodeCall(
                governor.propose,
                (
                    proposal.targets,
                    proposal.values,
                    proposal.signatures,
                    proposal.calldatas,
                    proposal.description
                )
            ),
            "Invalid proposal calldata"
        );

        // Get enough RAD to pass the vote
        deal(address(RAD), address(this), governor.quorumVotes());
        RAD.delegate(address(this));
        vm.roll(block.number + 1);

        // Pass the vote
        uint256 proposalId = abi.decode(Address.functionCall(address(governor), data), (uint256));
        vm.roll(block.number + governor.votingDelay() + 1);
        governor.castVote(proposalId, true);
        vm.roll(block.number + governor.votingPeriod());
        governor.queue(proposalId);
        skip(TIMELOCK.delay());

        // State without executing the proposal
        skip(duration + drips.cycleSecs());
        uint128 usdcReceivable = drips.receiveStreamsResult(
            receiverId, USDC, duration + drips.cycleSecs() / drips.cycleSecs()
        );
        uint128 radReceivable = drips.receiveStreamsResult(
            receiverId, IERC20(address(RAD)), duration + drips.cycleSecs() / drips.cycleSecs()
        );
        rewind(duration + drips.cycleSecs());
        uint256 usdcTimelock = USDC.balanceOf(address(TIMELOCK));
        uint256 radTimelock = RAD.balanceOf(address(TIMELOCK));

        // Execute the proposal
        governor.execute(proposalId);

        // Verify the USDC transfer
        assertEq(
            USDC.balanceOf(address(TIMELOCK)),
            usdcTimelock - amtUsdc,
            "Invalid Timelock USDC balance"
        );
        assertEq(
            USDC.allowance(address(TIMELOCK), address(ADDRESS_DRIVER)), 0, "Unused USDC allowance"
        );

        // Verify the Rad transfer
        assertEq(
            RAD.balanceOf(address(TIMELOCK)), radTimelock - amtRad, "Invalid Timelock Rad balance"
        );
        assertEq(
            RAD.allowance(address(TIMELOCK), address(ADDRESS_DRIVER)), 0, "Unused Rad allowance"
        );

        // Verify the USDC stream
        {
            (,,, uint128 balance, uint32 maxEnd) = drips.streamsState(timelockAccountId, USDC);
            assertEq(balance, amtUsdc, "Invalid USDC stream balance");
            assertApproxEqAbs(maxEnd, block.timestamp + duration, 1, "Invalid USDC stream end");
        }
        {
            uint32 streamEnd = uint32(block.timestamp + duration + drips.cycleSecs());
            uint256 dust = amtUsdc / duration + 1;
            assertApproxEqAbs(
                drips.balanceAt(timelockAccountId, USDC, usdcReceivers, streamEnd),
                0,
                dust,
                "Invalid USDC stream balance after streaming"
            );
        }

        // Verify the Rad stream
        {
            (,,, uint128 balance, uint32 maxEnd) =
                drips.streamsState(timelockAccountId, IERC20(address(RAD)));
            assertEq(balance, amtRad, "Invalid Rad stream balance");
            assertApproxEqAbs(maxEnd, block.timestamp + duration, 1, "Invalid Rad stream end");
        }
        {
            uint32 streamEnd = uint32(block.timestamp + duration + drips.cycleSecs());
            uint256 dust = amtUsdc / duration + 1;
            assertApproxEqAbs(
                drips.balanceAt(timelockAccountId, IERC20(address(RAD)), radReceivers, streamEnd),
                0,
                dust,
                "Invalid Rad stream balance after streaming"
            );
        }

        // Verify the USDC stream receiver after streaming
        skip(duration + drips.cycleSecs());
        assertApproxEqAbs(
            drips.receiveStreamsResult(
                receiverId, USDC, duration + drips.cycleSecs() / drips.cycleSecs()
            ),
            usdcReceivable + amtUsdc,
            amtUsdc / duration + 1,
            "Invalid receivable USDC amount after streaming"
        );

        // Verify the Rad stream receiver after streaming
        assertApproxEqAbs(
            drips.receiveStreamsResult(
                receiverId, IERC20(address(RAD)), duration + drips.cycleSecs() / drips.cycleSecs()
            ),
            radReceivable + amtRad,
            amtRad / duration + 1,
            "Invalid receivable Rad amount after streaming"
        );
    }
}
