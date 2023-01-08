rule whoChangedBalanceOfToken(method f, address erc20)
    //filtered{f->f.selector==pause().selector}
 {
    env e;
    calldataarg args;

    //bytes32 pausedSlotBefore = pausedSlot(e);
    bytes32 getPausedSlotBefore = getPausedSlot(e);

    //bytes32 _storageSlotBefore = _storageSlot(e);
    bytes32 get_storageSlotBefore = get_storageSlot(e);

    uint256 balanceBefore = totalBalance(e, erc20);

    //require pausedSlotBefore == 0x2d3dd64cfe36f9c22b4321979818bccfbeada88f68e06ff08869db50f24e4d58;
    //require _storageSlotBefore == 0xe2eace0883e57721da7c6d5421826cf6852312431246618b5b53d0cb70e28a0a;

    f(e,args);

    //bytes32 pausedSlotAfter = pausedSlot(e);
    bytes32 getPausedSlotAfter = getPausedSlot(e);

    //bytes32 _storageSlotAfter = _storageSlot(e);
    bytes32 get_storageSlotAfter = get_storageSlot(e);

    uint256 balanceAfter = totalBalance(e, erc20);

    assert balanceBefore == balanceAfter, "balanceOfToken changed";

    //assert false;  // sanity
}