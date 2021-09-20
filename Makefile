install     : install_solc dapp_update yarn_install
install_solc:; nix-env -f https://github.com/dapphub/dapptools/archive/master.tar.gz -iA solc-static-versions.solc_0_8_7
dapp_update :; dapp update
yarn_install:; yarn install

build       :; dapp build
clean       :; dapp clean

prettier    :; yarn run prettier
lint        :; yarn run lint
test        :; dapp test
test_deep   :; dapp test --fuzz-runs 50000
