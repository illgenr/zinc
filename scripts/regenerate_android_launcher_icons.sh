#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_png="${repo_root}/src/assets/icon.png"
android_res="${repo_root}/android/res"

if [[ ! -f "${source_png}" ]]; then
  echo "Missing source icon: ${source_png}" >&2
  exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
  echo "Missing ImageMagick (need 'magick' on PATH)" >&2
  exit 1
fi

declare -a specs=(
  "mdpi 48"
  "hdpi 72"
  "xhdpi 96"
  "xxhdpi 144"
  "xxxhdpi 192"
)

for spec in "${specs[@]}"; do
  read -r density px <<<"${spec}"
  out_dir="${android_res}/mipmap-${density}"
  mkdir -p "${out_dir}"

  magick "${source_png}" \
    -resize "${px}x${px}" \
    -filter Lanczos \
    -define filter:blur=0.98 \
    "${out_dir}/ic_launcher.png"

  cp "${out_dir}/ic_launcher.png" "${out_dir}/ic_launcher_round.png"
done

echo "Regenerated Android launcher icons under: ${android_res}/mipmap-*/ic_launcher*.png"

