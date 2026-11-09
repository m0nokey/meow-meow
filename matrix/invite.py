import fcntl
import os
import secrets
import time
from pathlib import Path

import requests
import yaml

from synapse._scripts.register_new_matrix_user import request_registration


LOCAL_URL = "http://127.0.0.1:8008"
config = yaml.safe_load(Path("/data/homeserver.yaml").read_text())

if not config.get("registration_requires_token"):
    raise SystemExit("The homeserver is not configured for invitation-only registration.")

os.umask(0o077)
with open("/data/invite-admin.secret", "a+", encoding="utf-8") as credentials:
    fcntl.flock(credentials, fcntl.LOCK_EX)
    credentials.seek(0)
    username, _, password = credentials.read().partition(":")
    if not password:
        username = f"invite-admin-{secrets.token_hex(12)}"
        password = secrets.token_urlsafe(48)
        request_registration(username, password, LOCAL_URL, config["registration_shared_secret"], admin=True)
        credentials.write(f"{username}:{password}")

with requests.Session() as session:
    response = session.post(
        f"{LOCAL_URL}/_matrix/client/v3/login",
        json={
            "type": "m.login.password",
            "identifier": {"type": "m.id.user", "user": username},
            "password": password,
            "initial_device_display_name": "Local invite issuer",
        },
        timeout=10,
    )
    response.raise_for_status()
    session.headers["Authorization"] = f"Bearer {response.json()['access_token']}"
    try:
        invitation = session.post(
            f"{LOCAL_URL}/_synapse/admin/v1/registration_tokens/new",
            json={"token": secrets.token_urlsafe(32), "uses_allowed": 1, "expiry_time": int((time.time() + 3600) * 1000)},
            timeout=10,
        )
        invitation.raise_for_status()
    finally:
        session.post(f"{LOCAL_URL}/_matrix/client/v3/logout", timeout=10).raise_for_status()

print(f"{config['public_baseurl'].rstrip('/')}/join/#{invitation.json()['token']}")
