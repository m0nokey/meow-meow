#!/usr/bin/env bash
set -euo pipefail

mode=$1
source_dir=$(pwd)
runtime="$HOME/Downloads/meow-meow"
export IMAGE_MODE=build

compose() {
    docker compose --project-directory "$runtime" --env-file "$runtime/.env.$mode" \
        -f "$runtime/compose.yaml" -f "$runtime/compose.$mode.yaml" "$@"
}
cleanup() {
    if [[ -f $runtime/.env.$mode ]]; then
        compose down --remove-orphans
    fi
}
trap cleanup EXIT

"$source_dir/run.sh" "$mode"

for _ in {1..15}; do
    if compose exec -T nginx wget -qO- http://127.0.0.1:8080/ > "$RUNNER_TEMP/meow-index.html"; then
        break
    fi
    sleep 2
done
cmp "$source_dir/nginx/html/index.html" "$RUNNER_TEMP/meow-index.html"

if [[ $mode == tor ]]; then
    # Verify the live rule set and make an actual direct connection attempt.
    for _ in {1..15}; do
        if compose exec -T cloudflared sh -ec 'iptables -S OUTPUT | grep -qx -- "-P OUTPUT DROP"'; then
            break
        fi
        sleep 2
    done
    compose exec -T cloudflared sh -ec '
        iptables -S OUTPUT | grep -qx -- "-P OUTPUT DROP"
        iptables -C OUTPUT -p tcp -d "$RELAY_IP" --dport 9095 -j ACCEPT
        iptables -t nat -C OUTPUT -p tcp -d 198.19.0.0/16 -j REDIRECT --to-ports 7893
        su-exec nobody curl -fsS --max-time 5 "http://$ORIGIN_IP:8080/" >/dev/null
        ! su-exec nobody curl -sS --noproxy "*" --connect-timeout 3 --max-time 5 https://1.1.1.1/ >/dev/null 2>&1
    '
    relay_ready=0
    for _ in {1..24}; do
        if compose exec -T cloudflared sh -ec '
            dig @127.0.0.1 +short +time=4 +tries=1 A api.trycloudflare.com | grep -q "^198\.19\."
            su-exec nobody curl -sS --noproxy "*" --connect-timeout 6 --max-time 8 \
                https://api.trycloudflare.com/ -o /dev/null
        '; then
            relay_ready=1
            break
        fi
        sleep 5
    done
    test "$relay_ready" -eq 1
    for service in tor_a haproxy; do
        compose exec -T "$service" /bin/sh -ec '
            test "$(id -u)" -ne 0
            test "$(readlink /etc/localtime)" = /usr/share/zoneinfo/UTC
            test "$(date +%z)" = +0000
            test -s /usr/share/meow-meow/runtime-packages.json
            test -s /lib/apk/db/installed
            test ! -d /etc/apk
            for program in wget nc telnet apk gcc make git; do
                if command -v "$program" >/dev/null; then
                    echo "Unexpected runtime program: $program" >&2
                    exit 1
                fi
            done
        '
    done
fi
