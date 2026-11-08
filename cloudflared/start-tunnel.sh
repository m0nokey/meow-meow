#!/bin/bash
set -euo pipefail

children=()
cleanup() {
    kill "${children[@]}" 2>/dev/null || true
    wait "${children[@]}" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 0' TERM INT

save_tunnel_url() {
    local line url=''
    local url_pattern='https://[a-z0-9-]+[.]trycloudflare[.]com'
    while IFS= read -r line; do
        if [[ $line =~ $url_pattern ]]; then
            url=${BASH_REMATCH[0]}
        fi
        if [[ -n $url && $line == *'Registered tunnel connection'* ]]; then
            printf '%s\n' "$url" > /run/tunnel-url.tmp
            mv -f /run/tunnel-url.tmp /run/tunnel-url
        fi
    done
}

rm -f /run/tunnel-url /run/tunnel-url.tmp

if [[ ${MEOW_MODE:?} == direct ]]; then
    cloudflared tunnel --protocol http2 --edge-ip-version 4 --grace-period 5s \
        --url http://nginx:8080 > >(save_tunnel_url) 2>&1 &
    children+=("$!")
    wait "${children[0]}"
    exit
fi
[[ $MEOW_MODE == tor ]] || exit 1

# These rules are installed in this container's network namespace.
iptables -w -P OUTPUT DROP
iptables -w -F OUTPUT
iptables -w -t nat -F OUTPUT
iptables -w -A OUTPUT -o lo -d 127.0.0.1/32 -j ACCEPT
iptables -w -A OUTPUT -p tcp -d "$RELAY_IP/32" --dport 9095 -j ACCEPT
iptables -w -A OUTPUT -p tcp -d "$ORIGIN_IP/32" --dport 8080 -j ACCEPT
ip route replace 198.19.0.0/16 dev lo src 127.0.0.1
iptables -w -t nat -A OUTPUT -p tcp -d 198.19.0.0/16 -j REDIRECT --to-ports 7893

sed "s/@RELAY_IP@/$RELAY_IP/g" /etc/meow/config.yaml > /tmp/meow-config.yaml
su-exec nobody meow -d /tmp -f /tmp/meow-config.yaml >/dev/null 2>&1 &
children+=("$!")

echo 'Waiting for Cloudflare DNS and HTTPS through Tor.'
for ((attempt = 1; attempt <= 30; attempt++)); do
    kill -0 "${children[0]}" || exit 1
    srv=$(dig @127.0.0.1 +short +time=8 +tries=1 SRV _v2-origintunneld._tcp.argotunnel.com 2>/dev/null || true)
    if [[ $srv =~ [[:space:]]7844[[:space:]] ]] &&
        su-exec nobody curl --noproxy api.trycloudflare.com -sS --connect-timeout 8 --max-time 15 \
            -o /dev/null https://api.trycloudflare.com/ 2>/dev/null; then
        su-exec nobody cloudflared tunnel --protocol http2 --edge-ip-version 4 \
            --grace-period 5s --url "http://$ORIGIN_IP:8080" > >(save_tunnel_url) 2>&1 &
        children+=("$!")
        wait -n "${children[@]}"
        exit 1
    fi
    sleep 5
done
echo 'Cloudflare DNS or HTTPS is unreachable through Tor.' >&2
exit 1
