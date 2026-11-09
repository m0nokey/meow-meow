#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

case "${1:-}" in
    direct|tor) mode=$1 ;;
    *) printf 'Usage: bash matrix/invite.sh direct|tor\n' >&2; exit 2 ;;
esac

docker compose --env-file "../.env.$mode" -f ../compose.yaml -f "../compose.$mode.yaml" -f ../compose.matrix.yaml \
    exec -T --user 0 synapse python - < invite.py
