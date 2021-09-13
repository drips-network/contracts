install     : install_solc update
install_solc:; nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_8_7
update      :; dapp update

build       :; dapp build
clean       :; dapp clean

test        :; dapp test
test_deep   :; dapp test --fuzz-runs 50000
