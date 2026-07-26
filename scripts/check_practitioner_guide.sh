#!/usr/bin/env bash
set -euo pipefail

guide_dir="${1:?guide source directory required}"
pdf="${2:?guide PDF required}"
log="${guide_dir}/build/main.log"

test -s "${pdf}"
test -s "${log}"

if grep -Eiq 'undefined citations|undefined references|LaTeX Error|Emergency stop|Fatal error' "${log}"; then
    grep -Ein 'undefined citations|undefined references|LaTeX Error|Emergency stop|Fatal error' "${log}"
    exit 1
fi

if grep -R -En '/Users/|/Dropbox/|CENSUS_API_KEY=|olp_[A-Za-z0-9]+' \
    "${guide_dir}" --exclude-dir=build; then
    echo "private path or credential-like text found in guide source" >&2
    exit 1
fi

pages="$(pdfinfo "${pdf}" | awk '/^Pages:/ {print $2}')"
test -n "${pages}"
if [ "${pages}" -lt 40 ]; then
    echo "practitioner guide is unexpectedly short: ${pages} pages" >&2
    exit 1
fi

echo "practitioner guide accepted: ${pages} pages"
