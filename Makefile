install     : forge_update yarn_install
forge_update :; forge update
yarn_install:; yarn install

build       :; forge build
clean       :; forge clean

prettier    :; yarn run prettier
lint        :; yarn run lint
test        :; forge test
