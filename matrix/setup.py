import os
from pathlib import Path
import secrets
import subprocess
import sys

import yaml


CONFIG = Path("/data/homeserver.yaml")


def configure():
    hostname = os.environ["SYNAPSE_SERVER_NAME"]
    if not CONFIG.exists():
        subprocess.run(["/start.py", "generate"], check=True)

    config = yaml.safe_load(CONFIG.read_text())
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

    stat = CONFIG.stat()
    temporary = CONFIG.with_suffix(".tmp")
    temporary.touch(mode=0o600)
    temporary.write_text(yaml.safe_dump(config, sort_keys=False))
    temporary.chmod(0o600)
    os.chown(temporary, stat.st_uid, stat.st_gid)
    temporary.replace(CONFIG)


configure()
