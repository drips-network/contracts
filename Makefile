.PHONY: *

install         :; forge install

build           :; forge build
clean           :; forge clean

prettier        :; forge fmt
lint            :; forge fmt --check
test            :; forge test
test_deep       :; FOUNDRY_FUZZ_RUNS=50000 forge test
