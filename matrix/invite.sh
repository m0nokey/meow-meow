#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"

case "${1:-}" in
    direct|tor) mode=$1 ;;
    *) printf 'Usage: bash matrix/invite.sh direct|tor\n' >&2; exit 2 ;;
esac

compose_args=(--env-file "../.env.$mode" -f ../compose.yaml -f "../compose.$mode.yaml" -f ../compose.matrix.yaml)
if [[ -f ../.matrix-secrets/synapse ]]; then
    compose_args+=(-f ../compose.matrix.postgres.yaml)
fi
invitation=$(docker compose "${compose_args[@]}" run --rm -T --no-deps --entrypoint python matrix-invite - < invite.py)
docker compose "${compose_args[@]}" exec -T synapse python -c \
    'from pathlib import Path; Path("/data/invite-admin.secret").unlink(missing_ok=True)'
printf '%s\n' "$invitation"
