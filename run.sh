#!/usr/bin/env bash
set -euo pipefail
umask 022

source_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)

menu() {
    local blue='' reset='' choice
    if [[ -t 1 ]]; then
        blue=$'\033[38;5;117m'
        reset=$'\033[0m'
        if [[ -n ${TERM:-} && ${TERM:-} != dumb ]] && command -v clear >/dev/null; then
            clear || true
        fi
    fi
    printf '%s1.%s direct\n' "$blue" "$reset"
    printf '%s2.%s tor\n\n' "$blue" "$reset"
    printf '%sx.%s exit\n\n' "$blue" "$reset"
    printf '%s?: %s' "$blue" "$reset"
    IFS= read -r choice || exit 0
    case "$choice" in
        1) mode=direct ;;
        2) mode=tor ;;
        x|X) exit 0 ;;
        *) printf 'Choose 1, 2 or x.\n' >&2; exit 1 ;;
    esac
}

case "$#:${1:-}" in
    0:) menu ;;
    1:direct|1:tor) mode=$1 ;;
    *) printf 'Usage: %s [direct|tor]\n' "$0" >&2; exit 1 ;;
esac

image_mode=${IMAGE_MODE:-pull}
case "$image_mode" in
    pull) registry=${IMAGE_REGISTRY-ghcr.io/m0nokey}; image_tag=${IMAGE_TAG:-latest} ;;
    build) registry=${IMAGE_REGISTRY-}; image_tag=${IMAGE_TAG:-local} ;;
    *) printf 'IMAGE_MODE must be pull or build.\n' >&2; exit 1 ;;
esac
image_prefix="${registry:+${registry%/}/}meow-meow"

host_os=$(uname -s)
host_uid=$(id -u)
compose_name=meow-meow
case "$host_os:$host_uid" in
    Linux:0)
        if [[ ${XDG_SESSION_TYPE:-} == x11 || ${XDG_SESSION_TYPE:-} == wayland ||
              -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]]; then
            printf 'Run as your desktop user, without sudo.\n' >&2
            exit 1
        fi
        project=/opt/meow-meow
        ;;
    Darwin:0) printf 'Run as your macOS user, without sudo.\n' >&2; exit 1 ;;
    Linux:*|Darwin:*) project="$(cd "$HOME" && pwd -P)/Downloads/meow-meow" ;;
    *) printf 'Use Linux or macOS with Docker Desktop.\n' >&2; exit 1 ;;
esac

sha256() {
    if [[ $host_os == Darwin ]]; then
        shasum -a 256 "$@"
    else
        sha256sum "$@"
    fi
}

if [[ $host_os == Linux && $host_uid != 0 ]]; then
    path_digest=$(printf '%s' "$project" | sha256)
    compose_name="meow-meow-${path_digest:0:12}"
fi

docker compose version >/dev/null
if [[ $(docker info --format '{{.OSType}}') != linux ]]; then
    printf 'Docker must be running Linux containers.\n' >&2
    exit 1
fi

mkdir -p "$project/nginx"
launch_lock="$project/.launch-lock"
if ! mkdir "$launch_lock" 2>/dev/null; then
    printf 'Another launch is in progress in %s.\n' "$project" >&2
    exit 1
fi
download=''
cleanup() {
    if [[ -n $download ]]; then
        rm -f "$download"
    fi
    rmdir "$launch_lock"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

if [[ $project != "$source_dir" ]]; then
    cp "$source_dir/run.sh" "$source_dir/compose.yaml" \
        "$source_dir/compose.direct.yaml" "$source_dir/compose.tor.yaml" "$project/"
    cp -R "$source_dir/lib" "$source_dir/network" "$project/"
    mkdir -p "$project/cloudflared"
    for config in .dockerignore Dockerfile meow.yaml resolv.conf start-tunnel.sh tunnel-url.sh; do
        cp "$source_dir/cloudflared/$config" "$project/cloudflared/"
    done
    cp "$source_dir/nginx/.dockerignore" "$source_dir/nginx/Dockerfile" "$source_dir/nginx/nginx.conf" "$project/nginx/"
fi
if [[ ! -e $project/nginx/html ]]; then
    if [[ -d $project/html ]]; then
        cp -Rp "$project/html" "$project/nginx/html"
    else
        cp -Rp "$source_dir/nginx/html" "$project/nginx/html"
    fi
fi

cd "$project"
export MEOW_PROJECT=$compose_name
compose_args=(--env-file ".env.$mode" -f compose.yaml -f "compose.$mode.yaml")
compose() {
    docker compose "${compose_args[@]}" "$@"
}

write_image_env() {
    printf 'MEOW_PROJECT=%s\nMEOW_IMAGE_PREFIX=%s\nMEOW_IMAGE_TAG=%s\n' \
        "$compose_name" "$image_prefix" "$image_tag"
}

if [[ $mode == tor ]]; then
    # shellcheck source=lib/network.sh
    source ./lib/network.sh
    uplink_subnet=$(network_subnet "${compose_name}_uplink" 10 0 256)
    tunnel_subnet=$(network_subnet "${compose_name}_tunnel" 172 16 16)
    relay_ip=$(subnet_ip "$tunnel_subnet" 4)

    # shellcheck source=lib/meow.sh
    source ./lib/meow.sh
    { write_image_env; write_tor_env; } > ".env.$mode"
else
    write_image_env > ".env.$mode"
fi

compose config --quiet
if [[ $image_mode == pull ]]; then
    compose pull --policy always
else
    if [[ $mode == tor ]]; then
        compose build tor_a haproxy
        ensure_meow_archive
    fi
    compose build cloudflared nginx
fi
compose up -d --no-build --pull never --remove-orphans

printf '\nProject: %s\nSite: %s/nginx/html/index.html\n' "$project" "$project"
printf -v project_command '%q' "$project"
printf -v compose_command ' %q' "${compose_args[@]}"
command_prefix="cd $project_command && docker compose$compose_command"
if [[ $mode == tor ]]; then
    printf '\nAllow about 1–2 minutes after startup for cloudflared to obtain a public URL from Cloudflare through the Tor network.\n'
else
    printf '\nAllow about 1–2 minutes after startup for cloudflared to obtain a public URL from Cloudflare.\n'
fi
printf '\n%s exec -T cloudflared /usr/local/bin/tunnel-url\n' "$command_prefix"
if [[ $mode == tor ]]; then
    printf '\nMonitor either Tor instance with Nyx.\n\n'
    printf '%s exec -it tor_a nyx --socket /run/tor/control.sock\n' "$command_prefix"
    printf '%s exec -it tor_b nyx --socket /run/tor/control.sock\n' "$command_prefix"
fi
