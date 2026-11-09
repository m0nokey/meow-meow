#!/bin/bash
set -euo pipefail

if [[ -s /run/tunnel-url ]] && timeout 3 bash -ec '
    exec 3<>/dev/tcp/127.0.0.1/20241
    printf "GET /ready HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" >&3
    read -r _ status _ <&3
    [[ $status == 200 ]]
' 2>/dev/null; then
    cat /run/tunnel-url
else
    printf 'Cloudflare tunnel is not connected. Try again shortly.\n' >&2
    exit 1
fi
