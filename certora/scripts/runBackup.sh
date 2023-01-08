# This is a backup that works with UpdateReceiverStatesHarness.sol
if [[ "$1" ]]
then
    RULE="--rule $1"
fi

if [[ "$2" ]]
then
    MSG=": $2"
fi

certoraRun  certora/harness/UpdateReceiverStatesHarness.sol \
            src/Reserve.sol \
            lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol \
--verify UpdateReceiverStatesHarness:certora/specs/DripsHubBackup.spec \
--link  UpdateReceiverStatesHarness:reserve=Reserve \
--packages openzeppelin-contracts=lib/openzeppelin-contracts/contracts \
--path . \
--solc solc8.15 \
--loop_iter 3 \
--optimistic_loop \
$RULE  \
--msg "radicle -$RULE $MSG" #\

# The goal of this script is the help run the tool
# without having to enter manually all the required
# parameters every time a test is executed
#
# The script should be executed from the terminal,
# with the project folder as the working folder
#
#
# The script can be run either with:
#
# 1) no parameters --> all the rules in the .spec file are tested
#    example:
#
#    ./certora/scripts/run.sh
# 
#
# 2) with one parameter only --> the parameter states the rule name
#    example, when the rule name is "integrityOfDeposit":
#
#    ./certora/scripts/run.sh integrityOfDeposit
#
#
# 3) with two parameters:
#     - the first parameter is the rule name, as in 2)
#     - the second parameter is an optional message to help distinguish the rule
#       the second parameter should be encircled "with quotes"
#    example:
#
#    ./certora/scripts/run.sh integrityOfDeposit "user should get X for any deposit"