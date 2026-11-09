# syntax=docker/dockerfile:1.19
FROM matrixdotorg/synapse:v1.164.2 AS upstream

FROM python:3.13.18-slim-trixie AS python-base

FROM python-base AS python-security
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl gcc libc6-dev libbluetooth-dev patch xz-utils
COPY cpython-security.patch /tmp/cpython-security.patch
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

FROM python-base
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
COPY --from=upstream --exclude=python* /usr/local/bin/ /usr/local/bin/
COPY --from=upstream /usr/local/lib/python3.13/site-packages/ /usr/local/lib/python3.13/site-packages/
COPY --from=upstream /start.py /start.py
COPY --from=upstream /conf/ /conf/
COPY --from=python-security /out/ /
COPY requirements-security.txt /tmp/requirements-security.txt
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && apt-get install -y --no-install-recommends libjemalloc2 libjpeg62-turbo libpq5 libwebp7 \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/local/lib/python3.13/__pycache__/poplib.*.pyc /usr/local/lib/python3.13/http/__pycache__/client.*.pyc \
    && python -m pip install --no-cache-dir --only-binary=:all: -r /tmp/requirements-security.txt \
    && python -m pip check \
    && python -m pip uninstall -y pip \
    && rm /tmp/requirements-security.txt \
    && install -d -m 0700 -o 991 -g 991 /data
USER 991:991
VOLUME /data
EXPOSE 8008/tcp
ENTRYPOINT ["/start.py"]
