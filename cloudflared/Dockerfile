# syntax=docker/dockerfile:1.7
FROM alpine:3.24 AS busybox-builder
ARG APORTS_COMMIT=35f5eb2864e50dd4448758d31f3e2a32f733ab84
RUN apk add --no-cache build-base bzip2 ca-certificates curl git linux-headers \
        openssl-dev patch python3
COPY --from=network_source runtime/build-busybox.sh runtime/minimize-busybox.py runtime/busybox-applets.txt /build-config/
WORKDIR /src
RUN /bin/sh /build-config/build-busybox.sh

FROM alpine:3.24 AS unpack
ARG TARGETARCH
ARG MEOW_VERSION
ARG MEOW_SHA256
WORKDIR /tmp/release-assets
COPY assets/ ./
RUN set -eu; \
    case "$TARGETARCH" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) exit 1 ;; esac; \
    archive="meow-$MEOW_VERSION-$arch-unknown-linux-musl.tar.gz"; \
    printf '%s  %s\n' "$MEOW_SHA256" "$archive" | sha256sum -c -; \
    mkdir unpacked; \
    tar -xzf "$archive" -C unpacked; \
    binary="$(find unpacked -type f -name meow -print -quit)"; \
    install -m 0755 "$binary" /usr/local/bin/meow

FROM cloudflare/cloudflared:latest AS cloudflared
FROM alpine:3.24 AS base
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
RUN apk add --no-cache bash ca-certificates "zlib>=1.4-r0" \
    && apk add --no-cache --virtual .utc-build tzdata \
    && cp /usr/share/zoneinfo/UTC /tmp/meow-meow-UTC \
    && apk del .utc-build \
    && install -D -m 0644 /tmp/meow-meow-UTC /usr/share/zoneinfo/UTC \
    && rm /tmp/meow-meow-UTC \
    && ln -snf /usr/share/zoneinfo/UTC /etc/localtime \
    && printf '%s\n' UTC > /etc/timezone
COPY --from=cloudflared /usr/local/bin/cloudflared /usr/local/bin/cloudflared
COPY start-tunnel.sh /usr/local/bin/start-tunnel.sh
COPY --chmod=0755 tunnel-url.sh /usr/local/bin/tunnel-url
ENV NO_AUTOUPDATE=true HOME=/tmp
WORKDIR /tmp
ENTRYPOINT ["/bin/bash", "/usr/local/bin/start-tunnel.sh"]

FROM base AS direct
COPY --from=busybox-builder /out/busybox /bin/busybox
RUN --mount=type=bind,from=network_source,source=runtime,target=/build-config \
    /bin/sh /build-config/prune-busybox-links.sh && rm -f /usr/bin/ssl_client
USER 65534:65534

FROM base AS tor
RUN apk add --no-cache bind-tools curl iproute2 iptables su-exec
COPY --from=unpack /usr/local/bin/meow /usr/local/bin/meow
COPY meow.yaml /etc/meow/config.yaml
COPY --from=busybox-builder /out/busybox /bin/busybox
RUN --mount=type=bind,from=network_source,source=runtime,target=/build-config \
    /bin/sh /build-config/prune-busybox-links.sh && rm -f /usr/bin/ssl_client
RUN meow -v
