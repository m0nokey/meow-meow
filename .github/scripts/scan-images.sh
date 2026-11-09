#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname -- "$0")/../.."
# shellcheck source=.github/scripts/images.sh
source .github/scripts/images.sh
grype=$1
architecture=$2
tag=$3
report_scope=$4
mkdir -p security-reports/before-vex security-reports/verified
"$grype" db update
export GRYPE_DB_AUTO_UPDATE=false

status=0
for image in "${images[@]}"; do
    reference="$IMAGE_REGISTRY/meow-meow-$image:$tag"
    image_id=$(docker image inspect --format '{{.Id}}' "$reference")
    report_name="grype-$image-$architecture"
    report="security-reports/$report_name"
    raw_sarif="security-reports/before-vex/$report_name.sarif"
    verified_sarif="security-reports/verified/$report_name.sarif"
    scan_tag="meow-vex.local/meow-meow-$image:${image_id#sha256:}"
    docker image tag "$image_id" "$scan_tag"
    target="docker:$scan_tag"

    "$grype" "$target" -o json > "$report.json"
    scan_args=("$target")
    if [[ $image != synapse && $image != postgres ]]; then
        python3 .github/scripts/image-vex.py "$image_id" "$scan_tag" "$report.json" "$report.openvex.json"
        if [[ -s $report.openvex.json ]]; then
            scan_args+=(--vex "$report.openvex.json")
        fi
    fi

    "$grype" "$target" -o sarif > "$raw_sarif"
    if [[ ${#scan_args[@]} -gt 1 ]]; then
        "$grype" "${scan_args[@]}" -o sarif
    else
        cat "$raw_sarif"
    fi |
        jq --arg id "meow-meow/$report_scope/$image/$architecture/" \
            '.runs[].automationDetails.id = $id' > "$verified_sarif"
    if ! "$grype" "${scan_args[@]}" --only-fixed --fail-on medium; then
        status=1
    fi
done

exit "$status"
