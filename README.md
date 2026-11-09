# Meow Meow

Test or share a local website with a free, temporary `*.trycloudflare.com` URL. Works without a custom domain or a Cloudflare account. Docker publishes no host ports.

- **direct** — Nginx serves the site and `cloudflared` connects directly to Cloudflare.
- **tor** — `cloudflared` reaches Cloudflare through meow-rs, HAProxy, and Tor. The container's direct internet access is blocked.

## Quick start

Requires Bash and Docker Compose on Linux or Docker Desktop on macOS. Images support `amd64` and `arm64`. Local builds require Docker Compose 2.17 or later.

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

Choose `1. app` to serve your site or `2. matrix` to run Matrix chat. Then choose `1. direct`, `2. tor`, or `x. exit`. To launch only your app from the command line, run `./run.sh direct` or `./run.sh tor`. Allow about 1–2 minutes for the tunnel to register. The launcher prints the command to get its URL and the Nyx commands in Tor mode.

Replace `nginx/html/index.html` in the deployment directory with your own site. The default page comes from [Torrentflix](https://github.com/m0nokey/torrentflix). The directory is `/opt/meow-meow` on a Linux server when launched as root and `$HOME/Downloads/meow-meow` when launched as a regular user.

To take the site offline, run this in the deployment directory. Replace `direct` with `tor` if you started Tor mode.

```sh
docker compose --env-file .env.direct -f compose.yaml -f compose.direct.yaml down
```

## Matrix chat

Add `matrix` to launch Synapse alongside Meow Meow. The same mode controls how the Cloudflare connector reaches the internet. Users open the resulting HTTPS address in Element X as their account provider.

```sh
./run.sh direct matrix
./run.sh tor matrix
```

Each mode gets its own tunnel, database, and deployment directory (`matrix-direct` or `matrix-tor` under the usual Meow Meow directory). The launcher prints the URL and the command for issuing an invitation. For example, on macOS:

```sh
cd "$HOME/Downloads/meow-meow/matrix-direct"
bash matrix/invite.sh direct
```

An invitation link is valid for one registration within one hour. New users choose their own username and password. To start a direct chat, enter the other person's full Matrix ID (`@username:<tunnel-hostname>`) in Element X.

The homepage displays the animated logo. Matrix routes require a supported Element User-Agent, and the browser invitation page uses separate registration routes. Synapse runs on an isolated network with no host ports. This profile provides messaging and file sharing. Voice and video calls are outside this profile.

Keep the tunnel running while using the test instance. A newly created Quick Tunnel gets a different hostname, and the launcher preserves the database if the hostname no longer matches. The two modes are separate homeservers, so their accounts and rooms are separate.

## Images

The launcher pulls `latest` from GHCR by default. If the images are unavailable, build locally:

```sh
IMAGE_MODE=build IMAGE_REGISTRY= IMAGE_TAG=local bash ./run.sh
```

Set `IMAGE_TAG=<commit-sha>` to select a specific published build. After the first publication, the repository owner must make the five GHCR packages public to enable anonymous pulls.

## CI

[Meow Meow CI](.github/workflows/ci.yml) builds and tests both modes on native `amd64` and `arm64` runners. It publishes five multi-architecture images from `main` after the checks pass. Grype blocks publication on fixable medium, high, or critical vulnerabilities and rescans `latest` daily at **03:17 UTC**. Scan reports are available in GitHub Code scanning and as workflow artifacts.
