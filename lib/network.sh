network_ids=$(docker network ls -q)
used_subnets=
if [ -n "$network_ids" ]; then
    # Docker returns one network ID per line.
    used_subnets=$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' $network_ids)
fi

subnet_free() {
    printf '%s\n' "$used_subnets" | awk -v candidate="$1" '
        function ip_number(ip, octets) {
            split(ip, octets, ".")
            return octets[1] * 16777216 + octets[2] * 65536 + octets[3] * 256 + octets[4]
        }
        BEGIN { wanted = ip_number(candidate) }
        /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+$/ {
            split($0, cidr, "/")
            size = 2 ^ (32 - cidr[2])
            start = int(ip_number(cidr[1]) / size) * size
            if (wanted < start + size && start < wanted + 8) exit 1
        }
    '
}

network_subnet() {
    network_name=$1
    first_octet=$2
    second_start=$3
    second_count=$4
    existing=$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' "$network_name" 2>/dev/null || true)
    if [ -n "$existing" ]; then
        printf '%s\n' "$existing" | awk -F '[./]' -v first="$first_octet" \
            -v second_start="$second_start" -v second_count="$second_count" '
            NF == 5 && $1 == first && $2 >= second_start && $2 < second_start + second_count && $4 % 8 == 0 && $5 == 29 {
                print $1 "." $2 "." $3 "." $4
                found = 1
                exit
            }
            END { if (!found) exit 1 }
        '
        return
    fi
    attempt=0
    while [ "$attempt" -lt 512 ]; do
        random_bytes=$(od -An -N3 -tu1 /dev/urandom)
        set -- $random_bytes
        candidate="$first_octet.$((second_start + $1 % second_count)).$2.$(($3 / 8 * 8))"
        if subnet_free "$candidate"; then
            printf '%s\n' "$candidate"
            return
        fi
        attempt=$((attempt + 1))
    done
    printf 'No free /29 subnet found for %s.\n' "$network_name" >&2
    return 1
}

subnet_ip() {
    printf '%s.%s\n' "${1%.*}" "$((${1##*.} + $2))"
}
