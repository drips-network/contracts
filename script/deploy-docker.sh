#!/bin/bash
set -euxo pipefail

echo Deploying contracts to anvil...

rm -f anvil_stdout
mkfifo anvil_stdout
anvil --dump-state ./anvil-state.json --host 0.0.0.0 > anvil_stdout &
anvil_pid=$!

while ! grep -q "Listening on 0.0.0.0:8545" < anvil_stdout; do
  sleep 1
  ps -p $anvil_pid > /dev/null
done

forge script --rpc-url localhost:8545 --broadcast --slow \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  script/LocalTestnet.sol:Deploy \
  || SCRIPT_STATUS=$?

kill -2 $anvil_pid
wait
rm anvil_stdout
exit ${SCRIPT_STATUS:-0}
