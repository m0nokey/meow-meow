#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname -- "$0")/../.."
# shellcheck source=.github/scripts/images.sh
source .github/scripts/images.sh
grype=$1
architecture=$2
tag=$3
report_scope=$4
mkdir -p security-reports
"$grype" db update
export GRYPE_DB_AUTO_UPDATE=false

status=0
{
    printf '### Image vulnerability scan (%s)\n\n' "$architecture"
    printf '| Image | Findings before VEX | Fixable medium or higher |\n'
    printf '| --- | ---: | --- |\n'
} >> "$GITHUB_STEP_SUMMARY"

for image in "${images[@]}"; do
    reference="$IMAGE_REGISTRY/meow-meow-$image:$tag"
    image_id=$(docker image inspect --format '{{.Id}}' "$reference")
    report="security-reports/grype-$image-$architecture"
    if [[ $image == tor || $image == haproxy ]]; then
        scan_tag="meow-vex.local/meow-meow-$image:${image_id#sha256:}"
        docker image tag "$image_id" "$scan_tag"
        target="docker:$scan_tag"
    else
        target="docker:$reference"
    fi

    "$grype" "$target" -o json > "$report.json"
    scan_args=("$target")
    if [[ $image == tor || $image == haproxy ]]; then
        python3 .github/scripts/image-vex.py "$image_id" "$scan_tag" "$report.json" "$report.openvex.json"
        if [[ -s $report.openvex.json ]]; then
            scan_args+=(--vex "$report.openvex.json")
        fi
    fi

    "$grype" "${scan_args[@]}" -o sarif |
        jq --arg id "meow-meow/$report_scope/$image/$architecture/" \
            '.runs[].automationDetails.id = $id' > "$report.sarif"
    result=pass
    if ! "$grype" "${scan_args[@]}" --only-fixed --fail-on medium; then
        status=1
        result=fail
    fi
    findings=$(jq '.matches | length' "$report.json")
    printf '| %s | %s | %s |\n' "$image" "$findings" "$result" >> "$GITHUB_STEP_SUMMARY"
done

exit "$status"
