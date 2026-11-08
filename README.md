# Meow Meow

Test or share a local website with a free, temporary `*.trycloudflare.com` URL. Works without a custom domain or a Cloudflare account. Docker publishes no host ports.

- **direct** — Nginx serves the site and `cloudflared` connects directly to Cloudflare.
- **tor** — `cloudflared` reaches Cloudflare through meow-rs, HAProxy, and Tor. The container's direct internet access is blocked.

## Quick start

Requires Bash and Docker Compose on Linux or Docker Desktop on macOS. Images support `amd64` and `arm64`.

```sh
git clone https://github.com/m0nokey/meow-meow.git
cd meow-meow
./run.sh
```

Or download with curl:

```sh
curl -fL https://github.com/m0nokey/meow-meow/archive/refs/heads/main.tar.gz -o meow-meow.tar.gz
mkdir -p meow-meow
tar -xzf meow-meow.tar.gz --strip-components=1 -C meow-meow
cd meow-meow
./run.sh
```

Choose `1. direct`, `2. tor`, or `x. exit`. You can also run `./run.sh direct` or `./run.sh tor`. Allow about 1–2 minutes for the tunnel to register. The launcher prints the command to get its URL and the Nyx commands in Tor mode.

Replace `nginx/html/index.html` in the deployment directory with your own site. The default page comes from [Torrentflix](https://github.com/m0nokey/torrentflix). The directory is `/opt/meow-meow` on a Linux server when launched as root and `$HOME/Downloads/meow-meow` when launched as a regular user.

To take the site offline, run this in the deployment directory. Replace `direct` with `tor` if you started Tor mode.

```sh
docker compose --env-file .env.direct -f compose.yaml -f compose.direct.yaml down
```

## Images

The launcher pulls `latest` from GHCR by default. If the images are unavailable, build locally:

```sh
IMAGE_MODE=build IMAGE_REGISTRY= IMAGE_TAG=local bash ./run.sh
```

Set `IMAGE_TAG=<commit-sha>` to select a specific published build. After the first publication, the repository owner must make the five GHCR packages public to enable anonymous pulls.

## CI

[Meow Meow CI](.github/workflows/ci.yml) builds and tests both modes on native `amd64` and `arm64` runners. It publishes five multi-architecture images from `main` after the checks pass. Grype blocks publication on fixable medium, high, or critical vulnerabilities and rescans `latest` daily at **03:17 UTC**. Scan reports are available in GitHub Code scanning and as workflow artifacts.
