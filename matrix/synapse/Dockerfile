# syntax=docker/dockerfile:1.7
FROM matrixdotorg/synapse:v1.164.2 AS upstream

FROM alpine:3.24 AS busybox-builder
ARG APORTS_COMMIT=35f5eb2864e50dd4448758d31f3e2a32f733ab84
RUN apk add --no-cache build-base bzip2 ca-certificates curl git linux-headers \
        openssl-dev patch python3
COPY --from=network_source runtime/build-busybox.sh runtime/minimize-busybox.py runtime/busybox-applets.txt /build-config/
WORKDIR /src
RUN /bin/sh /build-config/build-busybox.sh

FROM python:3.13.18-alpine3.24 AS python-base

FROM python-base AS build
RUN apk add --no-cache bluez-dev build-base curl libpq-dev linux-headers patch xz
COPY cpython-security.patch requirements-security.txt /tmp/
WORKDIR /tmp
RUN set -eu; \
    archive="Python-${PYTHON_VERSION}.tar.xz"; \
    curl -fsSL --retry 3 --retry-all-errors --connect-timeout 20 --max-time 300 \
        -o "$archive" "https://www.python.org/ftp/python/${PYTHON_VERSION}/$archive"; \
    printf '%s  %s\n' "$PYTHON_SHA256" "$archive" | sha256sum -c -; \
    tar -xf "$archive"; \
    cd "Python-$PYTHON_VERSION"; \
    patch --batch --fuzz=0 -p1 < /tmp/cpython-security.patch; \
    stdlib="$(python -c 'import sysconfig; print(sysconfig.get_path("stdlib"))')"; \
    socket_module="$(python -c 'import _socket; print(_socket.__file__)')"; \
    install -D -m 0644 Lib/poplib.py "/out$stdlib/poplib.py"; \
    install -D -m 0644 Lib/http/client.py "/out$stdlib/http/client.py"; \
    mkdir -p "/out$(dirname "$socket_module")"; \
    gcc -shared -fPIC -O2 -Werror=implicit-function-declaration \
        -I"$PWD/Modules" -I"$(python -c 'import sysconfig; print(sysconfig.get_path("include"))')/internal" \
        $(python3-config --includes) Modules/socketmodule.c -o "/out$socket_module"
RUN python -m pip install --no-cache-dir --only-binary=:all: --no-binary=psycopg2,zope-interface \
    --prefix /out/usr/local -r /tmp/requirements-security.txt

FROM python-base
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
RUN apk upgrade --no-cache && apk add --no-cache libpq "zlib>=1.4-r0"
COPY --from=upstream /start.py /start.py
COPY --from=upstream /conf/ /conf/
COPY --from=build /out/ /
RUN python -m pip check \
    && rm -f /usr/local/lib/python3.13/__pycache__/poplib.*.pyc /usr/local/lib/python3.13/http/__pycache__/client.*.pyc \
    && python -m pip uninstall -y pip \
    && addgroup -S -g 991 synapse && adduser -S -D -H -u 991 -G synapse synapse \
    && install -d -m 0700 -o 991 -g 991 /data
COPY --from=busybox-builder /out/busybox /bin/busybox
RUN --mount=type=bind,from=network_source,source=runtime,target=/build-config \
    /bin/sh /build-config/prune-busybox-links.sh && rm -f /usr/bin/ssl_client
USER 991:991
VOLUME /data
EXPOSE 8008/tcp
ENTRYPOINT ["/start.py"]
