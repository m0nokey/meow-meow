#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname -- "$0")/../.."
runtime=$(mktemp -d)
project="meow-matrix-test-$(basename "$runtime" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]')"
export MEOW_IMAGE_PREFIX="${IMAGE_REGISTRY:+${IMAGE_REGISTRY%/}/}meow-meow"
export MEOW_IMAGE_TAG=${IMAGE_TAG:-local}
cp compose.yaml compose.direct.yaml compose.matrix.yaml compose.matrix.postgres.yaml "$runtime/"
cp -R matrix nginx network "$runtime/"
cd "$runtime"

base() {
    docker compose -p "$project" -f compose.yaml -f compose.direct.yaml -f compose.matrix.yaml "$@"
}
compose() {
    base -f compose.matrix.postgres.yaml "$@"
}
cleanup() {
    compose --profile operator down -v --remove-orphans
    docker compose -p "$project-legacy" -f compose.yaml -f compose.direct.yaml -f compose.matrix.yaml down -v
}
trap cleanup EXIT

(umask 077; mkdir .matrix-secrets)
for role in postgres synapse; do
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > ".matrix-secrets/$role"
    chmod 444 ".matrix-secrets/$role"
done

compose build synapse postgres
test "$(base run --rm -T --no-deps --entrypoint python synapse - database < matrix/setup.py)" = postgres
hostname=matrix.test
compose run --rm -T --no-deps -e SYNAPSE_SERVER_NAME="$hostname" \
    -v "$runtime/.matrix-secrets/synapse:/run/synapse-db-password:ro" \
    --entrypoint python synapse - < matrix/setup.py
compose up -d --no-deps --wait --wait-timeout 90 postgres
compose up -d --no-deps --wait --wait-timeout 90 synapse
test "$(compose exec -T postgres psql -U postgres -d postgres -Atqc \
    "SELECT rolname FROM pg_authid WHERE rolname='synapse' AND rolpassword LIKE 'SCRAM-SHA-256%' AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole")" = synapse

compose exec -T synapse python - <<'PY'
import secrets
from pathlib import Path
import yaml
from synapse._scripts.register_new_matrix_user import request_registration

config = yaml.safe_load(Path('/data/homeserver.yaml').read_text())
username = 'invite-admin-0123456789abcdef01234567'
request_registration(username, secrets.token_urlsafe(48), 'http://127.0.0.1:8008',
                     config['registration_shared_secret'], admin=True)
PY
docker run --rm --network none --user 0 -v "${project}_matrix_data:/data" --entrypoint python \
    "$MEOW_IMAGE_PREFIX-synapse:$MEOW_IMAGE_TAG" -c \
    'import os; from pathlib import Path; os.umask(0o077); Path("/data/invite-admin.secret").write_text("invite-admin-0123456789abcdef01234567:legacy-fixture")'
printf 'MEOW_PROJECT=%s\n' "$project" > .env.direct
invite=$(bash matrix/invite.sh direct)
test "$(compose exec -T postgres psql -U postgres -d synapse -Atqc \
    "SELECT count(*) FROM users WHERE (name LIKE '@invite-once-%' OR name = '@invite-admin-0123456789abcdef01234567:matrix.test') AND deactivated::integer = 1 AND password_hash IS NULL")" = 2
test "$(compose exec -T postgres psql -U postgres -d synapse -Atqc \
    "SELECT count(*) FROM access_tokens WHERE user_id LIKE '@invite-once-%' OR user_id = '@invite-admin-0123456789abcdef01234567:matrix.test'")" = 0
compose exec -T -e "MEOW_TEST_INVITE=${invite##*#}" synapse python - <<'PY'
import os
import secrets
from pathlib import Path
import requests
import yaml

assert os.getuid() == 991
assert not Path('/data/invite-admin.secret').exists()
with open('/proc/self/status') as status:
    assert 'CapEff:\t0000000000000000' in status.read()
assert yaml.safe_load(open('/data/homeserver.yaml'))['database']['name'] == 'psycopg2'
response = requests.get(
    'http://127.0.0.1:8008/_matrix/client/v1/register/m.login.registration_token/validity',
    params={'token': os.environ['MEOW_TEST_INVITE']}, timeout=5,
)
response.raise_for_status()
assert response.json() == {'valid': True}
base = 'http://127.0.0.1:8008/_matrix/client'
account = {'username': 'ci-user', 'password': secrets.token_urlsafe(32), 'inhibit_login': True}
response = requests.post(f'{base}/v3/register', json=account, timeout=10)
assert response.status_code == 401
for stage in next(flow['stages'] for flow in response.json()['flows'] if 'm.login.registration_token' in flow['stages']):
    auth = {'type': stage, 'token': os.environ['MEOW_TEST_INVITE'], 'session': response.json()['session']}
    response = requests.post(f'{base}/v3/register', json={**account, 'auth': auth}, timeout=10)
    if response.ok:
        break
response.raise_for_status()
response = requests.post(f'{base}/v3/login', json={
    'type': 'm.login.password', 'identifier': {'type': 'm.id.user', 'user': account['username']},
    'password': account['password'],
}, timeout=10)
response.raise_for_status()
headers = {'Authorization': f"Bearer {response.json()['access_token']}"}
response = requests.post(f'{base}/unstable/org.matrix.simplified_msc3575/sync', json={}, headers=headers, timeout=10)
response.raise_for_status()
assert response.json()['pos']
PY

legacy() {
    docker compose -p "$project-legacy" -f compose.yaml -f compose.direct.yaml -f compose.matrix.yaml "$@"
}
legacy run --rm -T --no-deps -e SYNAPSE_SERVER_NAME="$hostname" synapse generate
test "$(legacy run --rm -T --no-deps --entrypoint python synapse - database < matrix/setup.py)" = sqlite
legacy run --rm -T --no-deps -e SYNAPSE_SERVER_NAME="$hostname" \
    --entrypoint python synapse - < matrix/setup.py
legacy up -d --no-deps --wait --wait-timeout 90 synapse
