#!/bin/bash

set -euo pipefail

repository="uinaf/slopwake"
install_directory="${SLOPWAKE_INSTALL_DIR:-${HOME}/Applications}"
requested_version="latest"
replace_existing=false
temporary_directory=""
install_staging_directory=""
backup_app=""

usage() {
  cat <<'EOF'
Install the signed and notarized slopwake app from GitHub Releases.

Usage: install.sh [--version VERSION] [--install-dir DIRECTORY] [--force]

Options:
  --version VERSION       Install a specific release instead of the latest.
  --install-dir DIRECTORY Install into DIRECTORY (default: ~/Applications).
  --force                 Replace an existing slopwake.app.
  -h, --help              Show this help.
EOF
}

fail() {
  printf 'slopwake installer: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  result=$?
  restore_failed=false
  trap - EXIT
  trap '' HUP INT TERM
  if [[ -n "$backup_app" && -e "$backup_app" && ! -e "$target_app" ]]; then
    if ! mv "$backup_app" "$target_app"; then
      restore_failed=true
      printf 'slopwake installer: could not restore %s\n' "$target_app" >&2
      printf 'slopwake installer: previous app preserved at %s\n' "$backup_app" >&2
      if ((result == 0)); then
        result=1
      fi
    fi
  fi
  if [[ -n "$install_staging_directory" && -d "$install_staging_directory" ]]; then
    if [[ "$restore_failed" == true && -e "$backup_app" ]]; then
      printf 'slopwake installer: recovery files preserved at %s\n' \
        "$install_staging_directory" >&2
    else
      rm -rf "$install_staging_directory"
    fi
  fi
  if [[ -n "$temporary_directory" && -d "$temporary_directory" ]]; then
    rm -rf "$temporary_directory"
  fi
  exit "$result"
}

while (($# > 0)); do
  case "$1" in
    --version)
      (($# >= 2)) || fail "--version requires a value"
      requested_version="$2"
      shift 2
      ;;
    --install-dir)
      (($# >= 2)) || fail "--install-dir requires a value"
      install_directory="$2"
      shift 2
      ;;
    --force)
      replace_existing=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"
[[ -n "$install_directory" ]] || fail "install directory cannot be empty"

for command in curl plutil shasum ditto codesign spctl sw_vers awk; do
  command -v "$command" >/dev/null 2>&1 || fail "required command is unavailable: $command"
done

macos_version="$(sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
[[ "$macos_major" =~ ^[0-9]+$ ]] || fail "could not determine the macOS version"
((macos_major >= 26)) || fail "macOS 26 or newer is required"

if [[ "$requested_version" != "latest" ]]; then
  requested_version="${requested_version#v}"
  [[ "$requested_version" =~ ^[0-9]+([.][0-9]+){2}([+_-][A-Za-z0-9.-]+)?$ ]] ||
    fail "invalid version: $requested_version"
fi

target_app="${install_directory%/}/slopwake.app"
if [[ -e "$target_app" && "$replace_existing" != true ]]; then
  fail "${target_app} already exists; rerun with --force to replace it"
fi

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/slopwake-install.XXXXXX")"
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

metadata_path="${temporary_directory}/release.json"
if [[ "$requested_version" == "latest" ]]; then
  metadata_url="https://api.github.com/repos/${repository}/releases/latest"
else
  metadata_url="https://api.github.com/repos/${repository}/releases/tags/v${requested_version}"
fi
curl --fail --silent --show-error --location "$metadata_url" --output "$metadata_path"

release_tag="$(plutil -extract tag_name raw -o - "$metadata_path" 2>/dev/null)" ||
  fail "release metadata has no tag"
version="${release_tag#v}"
[[ "$version" =~ ^[0-9]+([.][0-9]+){2}([+_-][A-Za-z0-9.-]+)?$ ]] ||
  fail "release metadata has an invalid version"
if [[ "$requested_version" != "latest" && "$version" != "$requested_version" ]]; then
  fail "release metadata version does not match v${requested_version}"
fi

asset_name="slopwake-${version}-macos-universal.zip"
asset_count="$(plutil -extract assets raw -o - "$metadata_path" 2>/dev/null)" ||
  fail "release metadata has no assets"
[[ "$asset_count" =~ ^[0-9]+$ ]] || fail "release metadata has an invalid asset count"

asset_url=""
expected_digest=""
for ((index = 0; index < asset_count; index++)); do
  name="$(plutil -extract "assets.${index}.name" raw -o - "$metadata_path" 2>/dev/null || true)"
  [[ "$name" == "$asset_name" ]] || continue
  asset_url="$(plutil -extract "assets.${index}.browser_download_url" raw -o - "$metadata_path" 2>/dev/null || true)"
  expected_digest="$(plutil -extract "assets.${index}.digest" raw -o - "$metadata_path" 2>/dev/null || true)"
  break
done

[[ "$asset_url" == "https://github.com/${repository}/releases/download/v${version}/${asset_name}" ]] ||
  fail "release metadata has no trusted download URL for ${asset_name}"
[[ "$expected_digest" =~ ^sha256:[0-9a-f]{64}$ ]] ||
  fail "release metadata has no SHA-256 digest for ${asset_name}"

archive_path="${temporary_directory}/${asset_name}"
curl --fail --silent --show-error --location "$asset_url" --output "$archive_path"
actual_digest="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
[[ "sha256:${actual_digest}" == "$expected_digest" ]] || fail "download checksum mismatch"

extraction_directory="${temporary_directory}/extracted"
mkdir -p "$extraction_directory"
ditto -x -k "$archive_path" "$extraction_directory"
source_app="${extraction_directory}/slopwake.app"
[[ -d "$source_app" ]] || fail "archive does not contain slopwake.app"

info_plist="${source_app}/Contents/Info.plist"
bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist" 2>/dev/null || true)"
bundle_version="$(plutil -extract CFBundleShortVersionString raw -o - "$info_plist" 2>/dev/null || true)"
[[ "$bundle_identifier" == "dev.uinaf.slopwake" ]] || fail "unexpected app bundle identifier"
[[ "$bundle_version" == "$version" ]] || fail "app version does not match the release"
codesign --verify --deep --strict --verbose=2 "$source_app"
spctl --assess --type execute --verbose=2 "$source_app"

mkdir -p "$install_directory"
install_staging_directory="$(mktemp -d "${install_directory%/}/.slopwake-install.XXXXXX")"
staged_app="${install_staging_directory}/slopwake.app"
backup_app="${install_staging_directory}/previous-slopwake.app"
ditto "$source_app" "$staged_app"
if [[ -e "$target_app" ]]; then
  mv "$target_app" "$backup_app"
fi
mv "$staged_app" "$target_app"

printf 'installed slopwake %s at %s\n' "$version" "$target_app"
