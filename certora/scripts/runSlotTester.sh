certoraRun  certora/SlotTester.sol \
--verify SlotTester:certora/specs/SlotTester.spec \
--path . \
--solc solc8.15 \
--loop_iter 3 \
--optimistic_loop \
--rule whoChangedBalanceOfToken  \
--msg "radicle --whoChangedBalanceOfToken -SlotTester private with getters for slots"