FROM postgres:18.6-alpine3.24
LABEL org.opencontainers.image.source="https://github.com/m0nokey/meow-meow"
RUN apk upgrade --no-cache && rm /usr/local/bin/gosu
COPY pg_hba.conf /etc/meow-pg-hba.conf
COPY --chmod=0755 init-synapse.sh /docker-entrypoint-initdb.d/10-synapse.sh
USER 70:70
