#!/usr/bin/env bash
set -euo pipefail

mode="${1:-build}"
case "${mode}" in
    build|check) ;;
    *) echo "usage: $0 [build|check]" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generated="${root}/docs/practitioner-guide/generated"
figures="${root}/docs/practitioner-guide/figures"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/tnw-guide-figures.XXXXXX")"
trap 'rm -rf "${temporary}"' EXIT

export SOURCE_DATE_EPOCH=946684800
export FORCE_SOURCE_DATE=1
export TZ=UTC

for stem in grid-network grid-decomposition; do
    mkdir -p "${temporary}/${stem}"
    latexmk -pdf -interaction=nonstopmode -halt-on-error \
        -outdir="${temporary}/${stem}" "${generated}/${stem}.tex" >/dev/null
    pdftocairo -png -singlefile -transp -r 180 \
        "${temporary}/${stem}/${stem}.pdf" "${temporary}/${stem}/${stem}" >/dev/null
    file "${temporary}/${stem}/${stem}.png" | grep -q "RGBA" ||
        { echo "${stem}.png does not have an alpha channel" >&2; exit 1; }
    if [[ "${mode}" == "build" ]]; then
        mkdir -p "${figures}"
        cp "${temporary}/${stem}/${stem}.pdf" "${figures}/${stem}.pdf"
        cp "${temporary}/${stem}/${stem}.png" "${figures}/${stem}.png"
    else
        pdftocairo -png -singlefile -transp -r 180 \
            "${figures}/${stem}.pdf" \
            "${temporary}/${stem}/${stem}-committed-pdf" >/dev/null
        python3 "${root}/scripts/compare_guide_images.py" \
            "${temporary}/${stem}/${stem}.png" \
            "${temporary}/${stem}/${stem}-committed-pdf.png"
        python3 "${root}/scripts/compare_guide_images.py" \
            "${temporary}/${stem}/${stem}.png" "${figures}/${stem}.png"
    fi
done

echo "practitioner-guide figures ${mode} accepted"
