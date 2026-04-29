FROM ghcr.io/foundry-rs/foundry:v1.7.0

WORKDIR /contracts
# This assures that `/contracts` is created with ownership useful for `RUN`
RUN true

COPY src src
COPY script script
COPY lib lib
COPY foundry.toml remappings.txt .
RUN /bin/bash ./script/deploy-docker.sh
RUN mkdir -p /contracts/anvil-data

ENTRYPOINT ["./script/docker-entrypoint.sh"]
