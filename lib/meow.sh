meow_version=v0.28.0
docker_platform=$(docker info --format '{{.OSType}}/{{.Architecture}}')
case "$docker_platform" in
    linux/x86_64|linux/amd64)
        arch=x86_64
        meow_asset_id=691309497
        meow_sha256=e46f3615e1b21ca720abebfb0cfbc8428d3c0885e12d1a80a40aa571c4a3bbda
        ;;
    linux/aarch64|linux/arm64)
        arch=aarch64
        meow_asset_id=691309493
        meow_sha256=65b5ef884e723a45b536e7794a4f2944a97d945cc9ef5ce468f303e0a0635af9
        ;;
    *) echo 'This installer requires Docker running Linux containers on amd64 or arm64.' >&2; exit 1 ;;
esac
archive_name="meow-$meow_version-$arch-unknown-linux-musl.tar.gz"
installed_archive="$project/cloudflared/assets/$archive_name"

verify_meow() {
    printf '%s  %s\n' "$meow_sha256" "$1" | sha256 -c - >/dev/null 2>&1
}

download_meow() {
    download_client=$1
    shift
    "$download_client" -q -fLsS --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 90 \
        -H 'Accept: application/octet-stream' -o - "$@" > "$download" &&
        verify_meow "$download"
}

tor_curl() {
    if [ "$host_uid" -ne 0 ]; then
        docker run --rm --log-driver none --network "container:$relay_container" curlimages/curl:latest "$@"
    else
        curl "$@"
    fi
}

download_meow_through_tor() {
    compose up -d --no-build --pull never tor_a tor_b haproxy || return 1
    if [ "$host_uid" -ne 0 ]; then
        relay_container=$(compose ps -q haproxy) || return 1
        [ -n "$relay_container" ] || return 1
        if ! docker image inspect curlimages/curl:latest >/dev/null 2>&1; then
            docker pull curlimages/curl:latest || return 1
        fi
    fi
    tor_proxy="$relay_ip:9095"
    printf 'Waiting for the Tor SOCKS relay at %s.\n' "$tor_proxy"
    attempt=0
    until tor_curl -q -sS --connect-timeout 6 --max-time 8 --noproxy '' \
        --socks5-hostname "$tor_proxy" -o /dev/null "${https_scheme}//cloudflare-dns.com/" 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 24 ]; then
            echo 'The Tor relay did not become ready.' >&2
            return 1
        fi
        sleep 5
    done
    printf 'Downloading %s through Tor.\n' "$archive_name"
    download_meow tor_curl --noproxy '' --socks5-hostname "$tor_proxy" "$release_url" ||
        download_meow tor_curl --noproxy '' --socks5-hostname "$tor_proxy" "$asset_url"
}

write_tor_env() {
    cat <<EOF
MEOW_VERSION=$meow_version
MEOW_SHA256=$meow_sha256
UPLINK_SUBNET=$uplink_subnet/29
UPLINK_GATEWAY=$(subnet_ip "$uplink_subnet" 1)
UPLINK_A_IP=$(subnet_ip "$uplink_subnet" 2)
UPLINK_B_IP=$(subnet_ip "$uplink_subnet" 3)
TUNNEL_SUBNET=$tunnel_subnet/29
TUNNEL_GATEWAY=$(subnet_ip "$tunnel_subnet" 1)
TOR_A_IP=$(subnet_ip "$tunnel_subnet" 2)
TOR_B_IP=$(subnet_ip "$tunnel_subnet" 3)
RELAY_IP=$relay_ip
ORIGIN_IP=$(subnet_ip "$tunnel_subnet" 5)
TUNNEL_IP=$(subnet_ip "$tunnel_subnet" 6)
EOF
}

ensure_meow_archive() {
    if verify_meow "$installed_archive"; then
        return
    fi
    mkdir -p "$project/cloudflared/assets"
    if verify_meow "$project/assets/$archive_name"; then
        cp "$project/assets/$archive_name" "$installed_archive"
        return
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo 'curl is required to download meow-rs.' >&2
        exit 1
    fi
    https_scheme=https:
    release_url="${https_scheme}//github.com/meow-rs/meow-rs/releases/download/$meow_version/$archive_name"
    asset_url="${https_scheme}//api.github.com/repos/meow-rs/meow-rs/releases/assets/$meow_asset_id"
    download=$(mktemp "$project/cloudflared/assets/.download.XXXXXX")
    if [ "${MEOW_FETCH_VIA_TOR:-0}" != 1 ] &&
        download_meow curl --max-time 35 --noproxy github.com,release-assets.githubusercontent.com "$release_url"; then
        :
    elif ! download_meow_through_tor; then
        echo 'Could not obtain a verified meow-rs archive. The cloudflared image was not built.' >&2
        exit 1
    fi
    mv -f "$download" "$installed_archive"
    download=''
}
