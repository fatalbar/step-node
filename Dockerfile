ARG SUBNET_ID=7f9jciLEX25NPJEaAz1X7XF44B1Q9UBwq6PdnCHm5mnUq1e1C
ARG SUBNET_NAME=StepNetwork
ARG VM_ID=dkjnKTbCTozMmvJJETzrz8sYVs7vSKzkGShHoa493UcQEweU6
ARG BLOCKCHAIN_ID=2jRZvKtXY5nyWTqRwFh1KMHGrCRxJoULu4r2CsayWRnjdDGbV1
# Changes to the minimum golang version must also be replicated in
# scripts/build_avalanche.sh
# scripts/local.Dockerfile
# Dockerfile (here)
# README.md
# go.mod
# ============= Compilation Stage ================
FROM golang:1.18.5-buster AS builder
ARG SUBNET_NAME
ARG SUBNET_ID
ARG VM_ID
ARG BLOCKCHAIN_ID
RUN apt-get update && apt-get install -y --no-install-recommends bash=5.0-4 git=1:2.20.1-2+deb10u3 make=4.2.1-1.2 gcc=4:8.3.0-1 musl-dev=1.1.21-2 ca-certificates=20200601~deb10u2 linux-headers-amd64

WORKDIR /build
# Copy and download avalanche dependencies using go mod
COPY go.mod .
COPY go.sum .
RUN go mod download

# Copy the code into the container
COPY . .

# Build avalanchego and plugins
RUN ./scripts/build.sh

# build subnet-evm
RUN cd subnet-evm && scripts/build.sh build/$VM_ID


# ============= Cleanup Stage ================
FROM debian:11-slim AS execution
ARG SUBNET_NAME
ARG SUBNET_ID
ARG VM_ID
ARG BLOCKCHAIN_ID
ENV BLOCKCHAIN_ID_ENV=$BLOCKCHAIN_ID
ENV FEE_RECIPIENT=0x6a07EDeD137F74dA55129836F8c29D72a3e3A588

RUN apt-get update
RUN apt-get install gettext-base

# Copy the executables into the container
COPY --from=builder /build/build /usr/local/lib/avalanchego
RUN ln -s /usr/local/lib/avalanchego/avalanchego /usr/local/bin/avalanchego
COPY --from=builder /build/subnet-evm/build/$VM_ID /usr/local/lib/avalanchego/plugins

ADD avalanchego-conf-templates templates
RUN mkdir -p /root/.avalanchego/configs/vms/
RUN cat templates/node.json | envsubst > /root/.avalanchego/config.json
RUN cat templates/aliases.json | envsubst > /root/.avalanchego/configs/vms/aliases.json

RUN mkdir -p /root/.avalanchego/configs/chains-relaxed/C
RUN cp templates/chains-c.json /root/.avalanchego/configs/chains-relaxed/C/config.json
RUN mkdir -p /root/.avalanchego/configs/chains-relaxed/$BLOCKCHAIN_ID
RUN cp templates/chains-subnet-relaxed.json /root/.avalanchego/configs/chains-relaxed/$BLOCKCHAIN_ID/config.json

RUN mkdir -p /root/.avalanchego/configs/chains-restricted/C
RUN cp templates/chains-c.json /root/.avalanchego/configs/chains-restricted/C/config.json
RUN mkdir -p /root/.avalanchego/configs/chains-restricted/$BLOCKCHAIN_ID
RUN cp templates/chains-subnet-restricted.json /root/.avalanchego/configs/chains-restricted/$BLOCKCHAIN_ID/config.json

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9650 9651
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
