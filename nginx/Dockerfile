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
USER 101:101
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]
