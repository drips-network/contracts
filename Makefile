install         :  forge_install yarn_install
forge_install   :; forge install
yarn_install    :; yarn install

build           :; forge build
clean           :; forge clean

prettier        :; yarn run prettier
lint            :; yarn run lint
test            :; forge test
test_deep       :; FOUNDRY_FUZZ_RUNS=50000 forge test
