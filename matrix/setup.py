import os
from pathlib import Path
import secrets
import subprocess
import sys

import yaml


CONFIG = Path("/data/homeserver.yaml")
DB_PASSWORD = Path("/run/synapse-db-password")


def configure():
    hostname = os.environ["SYNAPSE_SERVER_NAME"]
    if CONFIG.exists():
        config = yaml.safe_load(CONFIG.read_text())
        if config.get("database", {}).get("name") == "psycopg2":
            if config["database"]["args"]["password"] != DB_PASSWORD.read_text().strip():
                sys.exit("The PostgreSQL password file does not match the existing Synapse configuration.")
    else:
        generated = CONFIG.with_name(".generated-homeserver.yaml")
        generated.unlink(missing_ok=True)
        subprocess.run(
            ["/start.py", "generate"], check=True,
            env={**os.environ, "SYNAPSE_CONFIG_PATH": str(generated)},
        )
        config = yaml.safe_load(generated.read_text())
        generated.unlink()
        config["database"] = {
            "name": "psycopg2",
            "args": {
                "host": "postgres",
                "database": "synapse",
                "user": "synapse",
                "password": DB_PASSWORD.read_text().strip(),
                "cp_min": 1,
                "cp_max": 5,
            },
        }
    if config["server_name"] != hostname:
        sys.exit(
            f"This test database belongs to {config['server_name']}, "
            f"but Cloudflare assigned {hostname}. The existing database cannot use the new hostname."
        )

    config["public_baseurl"] = f"https://{hostname}/"
    config["enable_registration"] = True
    config["registration_requires_token"] = True
    config["allow_guest_access"] = False
    config["allow_public_rooms_without_auth"] = False
    config["allow_public_rooms_over_federation"] = False
    config["encryption_enabled_by_default_for_room_type"] = "all"
    config["federation_domain_whitelist"] = []
    config["url_preview_enabled"] = False
    config.setdefault("push", {})["include_content"] = False
    config.setdefault("registration_shared_secret", secrets.token_urlsafe(32))
    for listener in config["listeners"]:
        if listener["port"] == 8008:
            listener["x_forwarded"] = True
            listener["resources"] = [{"names": ["client"]}]

    temporary = CONFIG.with_suffix(".tmp")
    temporary.touch(mode=0o600)
    temporary.write_text(yaml.safe_dump(config, sort_keys=False))
    temporary.chmod(0o600)
    temporary.replace(CONFIG)


if sys.argv[1:] == ["database"]:
    if CONFIG.exists():
        database = yaml.safe_load(CONFIG.read_text()).get("database", {})
        print({"sqlite3": "sqlite", "psycopg2": "postgres"}[database.get("name", "sqlite3")])
    else:
        print("postgres")
else:
    configure()
