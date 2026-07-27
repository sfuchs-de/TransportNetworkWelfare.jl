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

for required in \
    grid-results.tex \
    example-results.tex \
    example-mechanisms.tex \
    rsue-results.tex \
    grid-network.pdf \
    grid-welfare-map.pdf \
    grid-scatter.pdf \
    grid-decomposition.pdf \
    grid-top-links.tex \
    braess-comparison.pdf \
    braess-top-links.tex \
    cow-comparison.pdf \
    cow-top-links.tex \
    urban-comparison.pdf \
    urban-top-links.tex \
    sioux-comparison.pdf \
    sioux-top-links.tex \
    seattle-network.pdf \
    seattle-mode-map.pdf \
    seattle-welfare-map.pdf \
    seattle-scatter.pdf \
    seattle-top-links.tex \
    westeros-world-map.pdf \
    westeros-scatter.pdf \
    westeros-top-links.tex \
    example-assets.json \
    external-example-assets.json \
    external-example-results.tex; do
    if ! find "${guide_dir}" -name "${required}" -type f -size +0c | grep -q .; then
        echo "missing generated guide asset: ${required}" >&2
        exit 1
    fi
done

if grep -R -En '/Users/|/Dropbox/|CENSUS_API_KEY=|olp_[A-Za-z0-9]+' \
    "${guide_dir}" --exclude-dir=build; then
    echo "private path or credential-like text found in guide source" >&2
    exit 1
fi

pages="$(pdfinfo "${pdf}" | awk '/^Pages:/ {print $2}')"
test -n "${pages}"
if [ "${pages}" -lt 35 ] || [ "${pages}" -gt 80 ]; then
    echo "practitioner guide is outside the 35--80 total-page target: ${pages} pages" >&2
    exit 1
fi

optimized="$(pdfinfo "${pdf}" | awk '/^Optimized:/ {print $2}')"
if [ "${optimized}" != "yes" ]; then
    echo "practitioner guide PDF is not linearized for web delivery" >&2
    exit 1
fi

echo "practitioner guide accepted: ${pages} pages"
