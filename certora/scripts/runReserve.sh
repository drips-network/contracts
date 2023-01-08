if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG=": $2"
fi

certoraRun  certora/harness/ReserveHarness.sol \
            certora/harness/DummyERC20Impl.sol \
            certora/harness/DummyERC20A.sol \
            certora/harness/DummyERC20B.sol \
--verify ReserveHarness:certora/specs/Reserve.spec \
--packages openzeppelin-contracts=lib/openzeppelin-contracts/contracts \
--path . \
--solc solc8.15 \
--loop_iter 3 \
--optimistic_loop \
$RULE  \
--msg "radicle Reserve-$RULE $MSG" \
--cloud \
--send_only \
--rule_sanity