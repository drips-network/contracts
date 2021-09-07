// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.6;

import "ds-test/test.sol";
import "./BaseTest.t.sol";

import {ERC721} from "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract TestNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor() ERC721("Test NFT", "TNFT") {}

    function mint(address receiver) external onlyOwner returns (uint256) {
        _tokenIds.increment();

        uint256 newNftTokenId = _tokenIds.current();
        _mint(receiver, newNftTokenId);

        return newNftTokenId;
    }
}

contract NFTPoolTest is BaseTest {
    Hevm public hevm;
    NFTPool pool;
    Dai dai;

    // test user
    User public alice;
    address public alice_;

    User public bob;
    address public bob_;

    TestNFT public nftRegistry;
    address public nftRegistry_;

    function setUp() public {
        hevm = Hevm(HEVM_ADDRESS);

        dai = new Dai();
        pool = new NFTPool(CYCLE_SECS, IDai(address(dai)));

        alice = new User(pool, dai);
        alice_ = address(alice);

        bob = new User(pool, dai);
        bob_ = address(bob);

        nftRegistry = new TestNFT();
        nftRegistry_ = address(nftRegistry);
    }

    function setupNFTStreaming(User from, address to, uint lockAmount, uint daiPerSecond) public returns (uint tokenId) {
        dai.transfer(address(from), lockAmount);

        tokenId = nftRegistry.mint(address(from));
        assertEq(nftRegistry.ownerOf(tokenId), address(from));

        from.streamWithNFT(nftRegistry_, tokenId, to, daiPerSecond, lockAmount);
        return tokenId;
    }

    function testBasicStreamWithNFT() public {
        uint lockAmount = 5_000 ether;
        // 1000 DAI per month
        uint daiPerSecond = 0.000001 ether;
        address to = alice_;
        User from = bob;

        // bob streams to alice
        uint tokenId = setupNFTStreaming(from, to, lockAmount, daiPerSecond);

        // two cycles
        uint t = 60 days;
        hevm.warp(block.timestamp + t);

        alice.collect();
        assertEqTol(dai.balanceOf(alice_), t * daiPerSecond, "incorrect received amount");

        // withdraw
        uint withdrawAmount = 30 ether;
        assertEq(dai.balanceOf(bob_), 0, "non-zero-balance");
        bob.withdraw(nftRegistry_, tokenId, withdrawAmount);
        assertEq(dai.balanceOf(bob_), withdrawAmount, "withdraw-fail");
    }

    function testFailWithdraw() public {
        uint lockAmount = 5_000 ether;
        // 1000 DAI per month
        uint daiPerSecond = 0.000001 ether;
        address to = alice_;
        User from = bob;

        // bob streams to alice
        uint tokenId = setupNFTStreaming(from, to, lockAmount, daiPerSecond);

        // transfer nft to random address
        bob.transferNFT(nftRegistry_, address(0x123), tokenId);
        uint withdrawAmount = 30 ether;
        bob.withdraw(nftRegistry_, tokenId, withdrawAmount);
    }

    function testTransferNFT() public {
        uint lockAmount = 5_000 ether;
        // 1000 DAI per month
        uint daiPerSecond = 0.000001 ether;
        address to = alice_;
        User from = bob;

        // bob streams to alice
        uint tokenId = setupNFTStreaming(from, to, lockAmount, daiPerSecond);

        User charly = new User(pool, dai);
        address charly_ = address(charly);

        // transfer nft to charly address
        bob.transferNFT(nftRegistry_, address(charly), tokenId);

        // charly withdraw
        uint withdrawAmount = 30 ether;
        assertEq(dai.balanceOf(charly_), 0, "non-zero-balance");
        charly.withdraw(nftRegistry_, tokenId, withdrawAmount);
        assertEq(dai.balanceOf(charly_), withdrawAmount, "withdraw-fail");
    }

    function testBasicNFTtoNFT() public {
        uint lockAmount = 5_000 ether;
        // 1000 DAI per month
        uint daiPerSecond = 0.000001 ether;

        uint aliceNFT = nftRegistry.mint(address(alice));
        uint bobNFT = nftRegistry.mint(address(bob));

        dai.transfer(bob_, lockAmount);

        // unique id for alice NFT
        address to = pool.nftID(nftRegistry_, uint128(aliceNFT));

        // bob streams to alice
        bob.streamWithNFT(nftRegistry_, bobNFT, to, daiPerSecond, lockAmount);

        // two cycles
        uint t = 60 days;
        hevm.warp(block.timestamp + t);

        // alice collects with her NFT
        alice.collect(nftRegistry_, aliceNFT);

        assertEqTol(dai.balanceOf(alice_), t * daiPerSecond, "incorrect received amount");
    }

    function testBasicAddressToNFT() public {
        uint lockAmount = 5_000 ether;
        // 1000 DAI per month
        uint daiPerCycle = 10 ether;
        uint daiPerSecond = fundingInSeconds(daiPerCycle);

        dai.transfer(bob_, lockAmount);

        uint aliceNFT = nftRegistry.mint(address(alice));
        // unique id for alice NFT
        address id = pool.nftID(nftRegistry_, uint128(aliceNFT));


        // bob streams with address to alice NFT
        bob.streamWithAddress(id, daiPerSecond, lockAmount);

        // two cycles
        uint t = 60 days;
        hevm.warp(block.timestamp + t);

        // alice collects with her NFT
        alice.collect(nftRegistry_, aliceNFT);

        assertEqTol(dai.balanceOf(alice_), t * daiPerSecond, "incorrect received amount");
    }
}
