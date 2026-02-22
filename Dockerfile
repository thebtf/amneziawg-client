# Build stage
FROM golang:1.24-alpine AS builder

RUN apk add --no-cache git make gcc musl-dev linux-headers

# Clone and build amneziawg-go
WORKDIR /build
RUN git clone https://github.com/amnezia-vpn/amneziawg-go.git . && \
    make

# Clone and build amneziawg-tools
WORKDIR /build-tools
RUN git clone https://github.com/amnezia-vpn/amneziawg-tools.git . && \
    cd src && \
    make

# Final stage
FROM alpine:latest

# Install required networking packages
RUN apk add --no-cache \
    bash \
    iptables \
    ip6tables \
    iproute2 \
    openresolv \
    wireguard-tools-wg-quick

# Copy binaries from builder
COPY --from=builder /build/amneziawg-go /usr/bin/amneziawg-go
COPY --from=builder /build-tools/src/wg /usr/bin/awg

# Note: wg-quick from wireguard-tools is used, but we alias it to awg-quick and make it call awg
# Since amneziawg-tools `make install` installs bash scripts for awg-quick, we can just copy them
COPY --from=builder /build-tools/src/wg-quick/linux.bash /usr/bin/awg-quick
RUN chmod +x /usr/bin/awg-quick

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create config directory
RUN mkdir -p /config

ENTRYPOINT ["/entrypoint.sh"]