meow_version=v0.28.0
docker_platform=$(docker info --format '{{.OSType}}/{{.Architecture}}')
case "$docker_platform" in
    linux/x86_64|linux/amd64)
        arch=x86_64
        meow_sha256=e46f3615e1b21ca720abebfb0cfbc8428d3c0885e12d1a80a40aa571c4a3bbda
        ;;
    linux/aarch64|linux/arm64)
        arch=aarch64
        meow_sha256=65b5ef884e723a45b536e7794a4f2944a97d945cc9ef5ce468f303e0a0635af9
        ;;
    *) echo 'This installer requires Docker running Linux containers on amd64 or arm64.' >&2; exit 1 ;;
esac
archive_name="meow-$meow_version-$arch-unknown-linux-musl.tar.gz"
installed_archive="$project/cloudflared/assets/$archive_name"

verify_meow() {
    printf '%s  %s\n' "$meow_sha256" "$1" | sha256 -c - >/dev/null 2>&1
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
    local release_url="https://github.com/meow-rs/meow-rs/releases/download/$meow_version/$archive_name"
    download=$(mktemp "$project/cloudflared/assets/.download.XXXXXX")
    if ! curl -q -fLsS --proto '=https' --proto-redir '=https' \
        --connect-timeout 15 --max-time 90 -o "$download" "$release_url" ||
        ! verify_meow "$download"; then
        echo 'Could not download or verify the meow-rs archive.' >&2
        exit 1
    fi
    mv -f "$download" "$installed_archive"
    download=''
}
