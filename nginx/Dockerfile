# syntax=docker/dockerfile:1.7
FROM alpine:3.24 AS busybox-builder
ARG APORTS_COMMIT=35f5eb2864e50dd4448758d31f3e2a32f733ab84
RUN apk add --no-cache build-base bzip2 ca-certificates curl git linux-headers \
        openssl-dev patch python3
COPY --from=network_source runtime/build-busybox.sh runtime/minimize-busybox.py runtime/busybox-applets.txt /build-config/
WORKDIR /src
RUN /bin/sh /build-config/build-busybox.sh

FROM nginx:alpine
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
RUN apk add --no-cache "zlib>=1.4-r0" \
    && apk add --no-cache --virtual .utc-build tzdata \
    && cp /usr/share/zoneinfo/UTC /tmp/meow-meow-UTC \
    && apk del .utc-build \
    && install -D -m 0644 /tmp/meow-meow-UTC /usr/share/zoneinfo/UTC \
    && rm /tmp/meow-meow-UTC \
    && ln -snf /usr/share/zoneinfo/UTC /etc/localtime \
    && printf '%s\n' UTC > /etc/timezone
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=busybox-builder /out/busybox /bin/busybox
RUN --mount=type=bind,from=network_source,source=runtime,target=/build-config \
    /bin/sh /build-config/prune-busybox-links.sh && rm -f /usr/bin/ssl_client
USER 101:101
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
