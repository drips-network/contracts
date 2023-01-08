if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG=": $2"
fi

certoraRun  certora/harness/SplitsHarness.sol \
--verify SplitsHarness:certora/specs/Splits2.spec \
--packages openzeppelin-contracts=lib/openzeppelin-contracts/contracts \
--path . \
--solc solc8.15 \
--loop_iter 2 \
--optimistic_loop \
$RULE  \
--msg "radicle Splits2-$RULE $MSG" \
--settings -t=2000,-mediumTimeout=800,-depth=100 \
--staging master \
--send_only \
--rule_sanity
