import hmac
import os
import re
import secrets
import stat
import time
from pathlib import Path
from urllib.parse import quote

import requests
import yaml

LOCAL_URL = "http://matrix-origin:8008"
config = yaml.safe_load(Path("/data/homeserver.yaml").read_text())

if not config.get("registration_requires_token"):
    raise SystemExit("The homeserver is not configured for invitation-only registration.")


def legacy_admin():
    try:
        descriptor = os.open("/data/invite-admin.secret", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return None
    with os.fdopen(descriptor, encoding="utf-8") as legacy:
        info = os.fstat(legacy.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
            raise SystemExit("Legacy invitation credentials must be a private, root-owned regular file.")
        username = legacy.readline(128).partition(":")[0]
        if not re.fullmatch(r"invite-admin-[0-9a-f]{24}", username):
            raise SystemExit("Unrecognized legacy invitation administrator.")
        return f"@{username}:{config['server_name']}"


def deactivate(session, user_id):
    response = session.post(
        f"{LOCAL_URL}/_synapse/admin/v1/deactivate/{quote(user_id, safe='')}", json={}, timeout=10,
    )
    response.raise_for_status()


def temporary_admin(session):
    endpoint = f"{LOCAL_URL}/_synapse/admin/v1/register"
    response = session.get(endpoint, timeout=10)
    response.raise_for_status()
    nonce = response.json()["nonce"]
    username = f"invite-once-{secrets.token_hex(12)}"
    password = secrets.token_urlsafe(48)
    # Synapse's shared-secret registration protocol specifies HMAC-SHA1.
    message = "\0".join((nonce, username, password, "admin")).encode()
    mac = hmac.digest(config["registration_shared_secret"].encode(), message, "sha1").hex()
    response = session.post(
        endpoint,
        json={"nonce": nonce, "username": username, "password": password, "admin": True, "mac": mac},
        timeout=10,
    )
    response.raise_for_status()
    return response.json()


previous_admin = legacy_admin()
with requests.Session() as session:
    login = temporary_admin(session)
    session.headers["Authorization"] = f"Bearer {login['access_token']}"
    try:
        if previous_admin:
            deactivate(session, previous_admin)
        invitation = session.post(
            f"{LOCAL_URL}/_synapse/admin/v1/registration_tokens/new",
            json={"token": secrets.token_urlsafe(32), "uses_allowed": 1, "expiry_time": int((time.time() + 3600) * 1000)},
            timeout=10,
        )
        invitation.raise_for_status()
    finally:
        deactivate(session, login["user_id"])

print(f"{config['public_baseurl'].rstrip('/')}/join/#{invitation.json()['token']}")
