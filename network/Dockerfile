# syntax=docker/dockerfile:1.7
ARG ALPINE_VERSION=3.24

FROM alpine:${ALPINE_VERSION} AS busybox-builder

# Keep Alpine's patches and command options while selecting only runtime applets.
ARG APORTS_COMMIT=35f5eb2864e50dd4448758d31f3e2a32f733ab84
RUN apk add --no-cache build-base bzip2 ca-certificates curl git linux-headers \
        openssl-dev patch python3

COPY runtime/build-busybox.sh runtime/minimize-busybox.py runtime/busybox-applets.txt /build-config/

WORKDIR /src
RUN /bin/sh /build-config/build-busybox.sh

FROM scratch AS hardened_busybox
COPY --from=busybox-builder /out/busybox /busybox
USER 65532:65532

FROM alpine:${ALPINE_VERSION} AS python-socket-builder
ARG PYTHON_VERSION=3.14.10
# The official source archive checksum from Alpine's Python package recipe.
ARG PYTHON_ARCHIVE_SHA512=730ea64f7e8815a5e1a4280b1205d77719875de630e6807b3140987b44e7b91215918cf75ed77250cf6feb5de98ff4175555cbba96eaf32564d2f421e723994a

RUN apk add --no-cache bluez-headers build-base ca-certificates curl linux-headers patch python3-dev xz
COPY runtime/build-python-socket.py runtime/socket-getaddrinfo.patch runtime/verify-socket.py /build-config/
WORKDIR /src
RUN set -eux; \
    archive="Python-${PYTHON_VERSION}.tar.xz"; \
    curl -fsS --connect-timeout 20 --max-time 300 --retry 3 --retry-all-errors \
        -o "${archive}" "https://www.python.org/ftp/python/${PYTHON_VERSION}/${archive}"; \
    printf '%s  %s\n' "${PYTHON_ARCHIVE_SHA512}" "${archive}" | sha512sum -c -; \
    tar -xf "${archive}"; \
    patch --batch --fuzz=0 -p1 -d "Python-${PYTHON_VERSION}" < /build-config/socket-getaddrinfo.patch; \
    export PYTHON_VERSION PYTHON_ARCHIVE_SHA512; \
    python3 /build-config/build-python-socket.py "Python-${PYTHON_VERSION}"

FROM scratch AS hardened_python_socket
COPY --from=python-socket-builder /out/ /runtime/
USER 65532:65532

FROM alpine:${ALPINE_VERSION} AS tor-runtime-files

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

# Install the stable runtime and explicitly pinned security revisions in one
# layer, then create the directories required by the non-root Tor process.
RUN apk add --no-cache \
        ca-certificates \
        tzdata \
        tor \
        nyx \
        xxd \
        procps-ng \
        python3 \
        "zlib>=1.4-r0" \
    && cp /usr/share/zoneinfo/UTC /tmp/meow-meow-UTC \
    && apk del tzdata \
    && install -d /usr/share/zoneinfo \
    && mv /tmp/meow-meow-UTC /usr/share/zoneinfo/UTC \
    && ln -snf /usr/share/zoneinfo/UTC /etc/localtime \
    && printf '%s\n' UTC > /etc/timezone \
    && apk add --no-cache \
        --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
        "expat>=2.8.4-r0" \
        "libexpat>=2.8.4-r0" \
        "libssl3>=3.5.8-r0" \
        "libcrypto3>=3.5.8-r0" \
        "sqlite-libs>=3.54.1-r0" \
    && addgroup -g 4242 -S torctl \
    && addgroup tor torctl \
    && install -d -m 0755 /usr/local/bin /etc/tor \
    && install -d -m 0700 -o tor -g tor /var/lib/tor \
    && install -d -m 0750 -o tor -g torctl /run/tor

COPY --chmod=0755 tor-control.py /usr/local/bin/tor-control
COPY --chmod=0755 tor/healthcheck.sh /usr/local/bin/healthcheck
COPY --chmod=0644 tor/torrc.template /etc/tor/torrc.template
COPY --chmod=0755 tor/entrypoint.sh /usr/local/bin/entrypoint-docker.sh

COPY --from=hardened_python_socket /runtime/ /
RUN --mount=type=bind,source=runtime,target=/run/python-security \
    /bin/sh /run/python-security/patch-python.sh

COPY --from=hardened_busybox /busybox /bin/busybox
RUN --mount=type=bind,source=runtime,target=/run/runtime-config \
    /bin/sh /run/runtime-config/prune-busybox-links.sh

FROM alpine:${ALPINE_VERSION} AS tor-assemble
RUN apk add --no-cache lddtreepax
COPY --from=tor-runtime-files / /source/
RUN --mount=type=bind,source=runtime,target=/run/runtime-config \
    python3 /run/runtime-config/stage-runtime.py exit

FROM scratch AS tor
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
COPY --from=tor-assemble /runtime/ /
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC
USER tor:torctl
ENTRYPOINT ["/usr/local/bin/entrypoint-docker.sh"]

FROM alpine:${ALPINE_VERSION} AS haproxy-runtime-files

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

# Install the stable runtime and explicitly pinned security revisions in one
# layer, then prepare the non-root HAProxy process.
RUN apk add --no-cache \
        ca-certificates \
        haproxy \
        tzdata \
        python3 \
        xxd \
        "zlib>=1.4-r0" \
    && cp /usr/share/zoneinfo/UTC /tmp/meow-meow-UTC \
    && apk del tzdata \
    && install -d /usr/share/zoneinfo \
    && mv /tmp/meow-meow-UTC /usr/share/zoneinfo/UTC \
    && ln -snf /usr/share/zoneinfo/UTC /etc/localtime \
    && printf '%s\n' UTC > /etc/timezone \
    && apk add --no-cache \
        --repository https://dl-cdn.alpinelinux.org/alpine/edge/main \
        "expat>=2.8.4-r0" \
        "libexpat>=2.8.4-r0" \
        "libssl3>=3.5.8-r0" \
        "libcrypto3>=3.5.8-r0" \
        "sqlite-libs>=3.54.1-r0" \
    && addgroup -g 4242 -S torctl \
    && addgroup haproxy torctl \
    && install -d -m 0755 /usr/local/bin /etc/haproxy \
    && ln -sf /usr/local/bin/tor-control /usr/bin/tor-control

COPY --chmod=0755 tor-control.py /usr/local/bin/tor-control
COPY --chmod=0755 haproxy/exit-ready-check.sh /usr/local/bin/exit_ready_check
COPY --chmod=0755 haproxy/render-haproxy-config.sh /usr/local/bin/render-haproxy-config
COPY --chmod=0644 haproxy/haproxy.cfg.template /etc/haproxy/haproxy.cfg.template
COPY --chmod=0755 haproxy/entrypoint.sh /usr/local/bin/entrypoint-docker.sh

COPY --from=hardened_python_socket /runtime/ /
RUN --mount=type=bind,source=runtime,target=/run/python-security \
    /bin/sh /run/python-security/patch-python.sh

COPY --from=hardened_busybox /busybox /bin/busybox
RUN --mount=type=bind,source=runtime,target=/run/runtime-config \
    /bin/sh /run/runtime-config/prune-busybox-links.sh

FROM alpine:${ALPINE_VERSION} AS haproxy-assemble
RUN apk add --no-cache lddtreepax
COPY --from=haproxy-runtime-files / /source/
RUN --mount=type=bind,source=runtime,target=/run/runtime-config \
    python3 /run/runtime-config/stage-runtime.py haproxy

FROM scratch AS haproxy
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
COPY --from=haproxy-assemble /runtime/ /
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC
USER haproxy:haproxy
ENTRYPOINT ["/usr/local/bin/entrypoint-docker.sh"]
