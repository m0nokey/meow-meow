FROM matrixdotorg/synapse:v1.164.2 AS upstream

FROM python:3.13.18-slim-trixie
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
COPY --from=upstream /usr/local/bin/ /usr/local/bin/
COPY --from=upstream /usr/local/lib/python3.13/site-packages/ /usr/local/lib/python3.13/site-packages/
COPY --from=upstream /start.py /start.py
COPY --from=upstream /conf/ /conf/
COPY requirements-security.txt /tmp/requirements-security.txt
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && apt-get install -y --no-install-recommends libjemalloc2 libjpeg62-turbo libpq5 libwebp7 \
    && rm -rf /var/lib/apt/lists/* \
    && python -m pip install --no-cache-dir --only-binary=:all: -r /tmp/requirements-security.txt \
    && python -m pip check \
    && python -m pip uninstall -y pip \
    && rm /tmp/requirements-security.txt \
    && install -d -m 0700 -o 991 -g 991 /data
USER 991:991
VOLUME /data
EXPOSE 8008/tcp
ENTRYPOINT ["/start.py"]
