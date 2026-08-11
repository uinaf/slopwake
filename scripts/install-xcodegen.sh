#!/usr/bin/env bash
set -euo pipefail

xcodegen_version="2.45.4"
xcodegen_sha256="090ec29491aad50aec10631bf6e62253fed733c50f3aab0f5ffc86bc170bdbef"
xcodegen_url="https://github.com/yonaskolb/XcodeGen/releases/download/${xcodegen_version}/xcodegen.zip"

destination="${1:-}"
if [[ -z "${destination}" ]]; then
  echo "usage: $0 <empty-install-directory>" >&2
  exit 64
fi

if [[ -e "${destination}/xcodegen" ]]; then
  echo "error: ${destination}/xcodegen already exists." >&2
  exit 1
fi

mkdir -p "${destination}"
archive="$(mktemp "${destination}/xcodegen.XXXXXX")"
trap 'rm -f "${archive}"' EXIT

curl \
  --fail \
  --location \
  --proto '=https' \
  --retry 3 \
  --show-error \
  --silent \
  --tlsv1.2 \
  --output "${archive}" \
  "${xcodegen_url}"

actual_sha256="$(shasum -a 256 "${archive}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${xcodegen_sha256}" ]]; then
  echo "error: XcodeGen ${xcodegen_version} checksum verification failed." >&2
  exit 1
fi

/usr/bin/ditto -x -k "${archive}" "${destination}"
"${destination}/xcodegen/bin/xcodegen" --version
