# syntax=docker/dockerfile:1.7
FROM alpine:3.24 AS busybox-builder
ARG APORTS_COMMIT=35f5eb2864e50dd4448758d31f3e2a32f733ab84
RUN apk add --no-cache build-base bzip2 ca-certificates curl git linux-headers \
        openssl-dev patch python3
COPY --from=network_source runtime/build-busybox.sh runtime/minimize-busybox.py runtime/busybox-applets.txt /build-config/
WORKDIR /src
RUN /bin/sh /build-config/build-busybox.sh

FROM postgres:18.6-alpine3.24
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
RUN apk upgrade --no-cache && rm /usr/local/bin/gosu
COPY pg_hba.conf /etc/meow-pg-hba.conf
COPY --chmod=0755 init-synapse.sh /docker-entrypoint-initdb.d/10-synapse.sh
COPY --from=busybox-builder /out/busybox /bin/busybox
RUN --mount=type=bind,from=network_source,source=runtime,target=/build-config \
    /bin/sh /build-config/prune-busybox-links.sh && rm -f /usr/bin/ssl_client
USER 70:70
