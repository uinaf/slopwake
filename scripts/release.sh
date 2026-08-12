#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "error: $1" >&2
  exit 1
}

required=(
  APPLE_DEVELOPER_ID_CERTIFICATE_P12_BASE64
  APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD
  APPLE_NOTARY_API_ISSUER_ID
  APPLE_NOTARY_API_KEY_ID
  APPLE_NOTARY_API_KEY_P8_BASE64
  APPLE_TEAM_ID
)
for name in "${required[@]}"; do
  [[ -n "${!name:-}" ]] || fail "${name} is required"
done

[[ -n "${RELEASE_VERSION:-}" ]] || fail "RELEASE_VERSION is required"
[[ "${RELEASE_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "RELEASE_VERSION must be a stable semantic version"

[[ "${APPLE_TEAM_ID}" =~ ^[A-Z0-9]{10}$ ]] || fail "APPLE_TEAM_ID is invalid"
[[ "${APPLE_NOTARY_API_KEY_ID}" =~ ^[A-Z0-9]{10}$ ]] || fail "APPLE_NOTARY_API_KEY_ID is invalid"
[[ "${APPLE_NOTARY_API_ISSUER_ID}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
  fail "APPLE_NOTARY_API_ISSUER_ID is invalid"

source_app="DerivedData/Build/Products/Release/slopwake.app"
[[ -d "${source_app}" ]] || fail "Release app is missing; run make build first"
source_version="$(plutil -extract CFBundleShortVersionString raw -o - "${source_app}/Contents/Info.plist")"
[[ "${source_version}" == "${RELEASE_VERSION}" ]] ||
  fail "Release app version ${source_version} does not match RELEASE_VERSION ${RELEASE_VERSION}"
source_bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "${source_app}/Contents/Info.plist")"
[[ "${source_bundle_identifier}" == "dev.uinaf.slopwake" ]] || fail "Release app bundle identifier is invalid"
source_executable="${source_app}/Contents/MacOS/slopwake"
actual_architectures="$(
  lipo -archs "${source_executable}" |
    tr ' ' '\n' |
    sort |
    tr '\n' ' '
)"
[[ "${actual_architectures}" == "arm64 x86_64 " ]] ||
  fail "Release executable must contain exactly arm64 and x86_64"

rcodesign_download=""
rcodesign_extract_root=""
secret_root=""
artifact_root=""
final_root=""
dist_archive=""
release_complete=false
cleanup() {
  [[ -z "${rcodesign_download}" ]] || rm -f "${rcodesign_download}"
  [[ -z "${secret_root}" ]] || rm -rf "${secret_root}"
  [[ -z "${rcodesign_extract_root}" ]] || rm -rf "${rcodesign_extract_root}"
  if [[ "${release_complete}" != true && -n "${artifact_root}" ]]; then
    rm -rf "${artifact_root}"
  fi
  if [[ "${release_complete}" != true && -n "${final_root}" ]]; then
    rm -rf "${final_root}"
  fi
  if [[ "${release_complete}" != true && -n "${dist_archive}" ]]; then
    rm -f "${dist_archive}"
  fi
}
trap cleanup EXIT

rcodesign_version="0.29.0"
rcodesign_archive="apple-codesign-${rcodesign_version}-macos-universal.tar.gz"
rcodesign_sha256="d98372d5524226ccf9dc0eda03d4e4f5826182dabb2fc3f2bd303ed9113a748d"
rcodesign_root=".artifacts/tools/apple-codesign-${rcodesign_version}"
rcodesign_archive_path="${rcodesign_root}/${rcodesign_archive}"
mkdir -p "${rcodesign_root}"
if [[ ! -f "${rcodesign_archive_path}" ]]; then
  rcodesign_download="$(mktemp "${rcodesign_root}/download.XXXXXX")"
  curl \
    --fail \
    --location \
    --proto '=https' \
    --retry 3 \
    --show-error \
    --silent \
    --tlsv1.2 \
    --output "${rcodesign_download}" \
    "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign%2F${rcodesign_version}/${rcodesign_archive}"
  actual_rcodesign_sha256="$(shasum -a 256 "${rcodesign_download}" | awk '{print $1}')"
  [[ "${actual_rcodesign_sha256}" == "${rcodesign_sha256}" ]] ||
    fail "rcodesign archive checksum mismatch"
  mv "${rcodesign_download}" "${rcodesign_archive_path}"
fi
actual_rcodesign_sha256="$(shasum -a 256 "${rcodesign_archive_path}" | awk '{print $1}')"
[[ "${actual_rcodesign_sha256}" == "${rcodesign_sha256}" ]] ||
  fail "cached rcodesign archive checksum mismatch"
rcodesign_extract_root="$(mktemp -d)"
tar -xzf "${rcodesign_archive_path}" -C "${rcodesign_extract_root}"
rcodesign="${rcodesign_extract_root}/apple-codesign-${rcodesign_version}-macos-universal/rcodesign"
[[ -x "${rcodesign}" ]] || fail "rcodesign is missing after extraction"

mkdir -p .artifacts/staging
artifact_root="$(mktemp -d .artifacts/staging/slopwake.XXXXXX)"
app="${artifact_root}/slopwake.app"
archive="${artifact_root}/slopwake-notarized.zip"
secret_root="$(mktemp -d)"
chmod 700 "${secret_root}"
certificate="${secret_root}/developer-id.p12"
certificate_password_file="${secret_root}/developer-id-password"
notary_key="${secret_root}/AuthKey_${APPLE_NOTARY_API_KEY_ID}.p8"

printf '%s' "${APPLE_DEVELOPER_ID_CERTIFICATE_P12_BASE64}" | /usr/bin/base64 -D >"${certificate}" ||
  fail "Developer ID certificate is not valid base64"
printf '%s' "${APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD}" >"${certificate_password_file}"
printf '%s' "${APPLE_NOTARY_API_KEY_P8_BASE64}" | /usr/bin/base64 -D >"${notary_key}" ||
  fail "notary API key is not valid base64"
chmod 600 "${certificate}" "${certificate_password_file}" "${notary_key}"
/usr/bin/openssl pkey -in "${notary_key}" -noout >/dev/null 2>&1 ||
  fail "notary API key is invalid"

/usr/bin/ditto "${source_app}" "${app}"
"${rcodesign}" sign \
  --p12-file "${certificate}" \
  --p12-password-file "${certificate_password_file}" \
  --for-notarization \
  "${app}"
codesign --verify --deep --strict --verbose=2 "${app}"
for architecture in arm64 x86_64; do
  signature_details="$(codesign --display --verbose=4 --arch "${architecture}" "${app}" 2>&1)"
  grep -q "^TeamIdentifier=${APPLE_TEAM_ID}$" <<<"${signature_details}" ||
    fail "${architecture} signature TeamIdentifier does not match APPLE_TEAM_ID"
  grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"${signature_details}" ||
    fail "${architecture} signature is missing the hardened runtime flag"
  grep -q '^Timestamp=' <<<"${signature_details}" ||
    fail "${architecture} signature is missing a trusted timestamp"
  grep -q '^Authority=Developer ID Application:' <<<"${signature_details}" ||
    fail "${architecture} signature is missing the Developer ID Application authority"
done

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${app}" "${archive}"
notary_result="${secret_root}/notary-result.plist"
submit_failed=false
xcrun notarytool submit "${archive}" \
  --key "${notary_key}" \
  --key-id "${APPLE_NOTARY_API_KEY_ID}" \
  --issuer "${APPLE_NOTARY_API_ISSUER_ID}" \
  --wait \
  --timeout 90m \
  --output-format plist >"${notary_result}" || submit_failed=true

notary_status="$(plutil -extract status raw -o - "${notary_result}" 2>/dev/null || true)"
submission_id="$(plutil -extract id raw -o - "${notary_result}" 2>/dev/null || true)"
if [[ "${submit_failed}" == true || "${notary_status}" != "Accepted" ]]; then
  echo "notarization submission: ${submission_id:-unavailable}" >&2
  if [[ -n "${submission_id}" ]]; then
  xcrun notarytool log \
    --key "${notary_key}" \
    --key-id "${APPLE_NOTARY_API_KEY_ID}" \
    --issuer "${APPLE_NOTARY_API_ISSUER_ID}" \
    "${submission_id}" >&2 || true
  fi
  fail "notarization failed with status ${notary_status:-unavailable}"
fi

xcrun stapler staple "${app}"
xcrun stapler validate "${app}"
codesign --verify --deep --strict --verbose=2 "${app}"
spctl --assess --type execute --verbose=4 "${app}"

rm -f "${archive}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${app}" "${archive}"

mkdir -p .artifacts/releases
candidate_final_root=".artifacts/releases/slopwake-${RELEASE_VERSION}.${submission_id}"
[[ ! -e "${candidate_final_root}" ]] || fail "release output already exists: ${candidate_final_root}"
final_root="${candidate_final_root}"
mv "${artifact_root}" "${final_root}"
mkdir -p dist
candidate_dist_archive="dist/slopwake-${RELEASE_VERSION}-macos-universal.zip"
[[ ! -e "${candidate_dist_archive}" ]] || fail "release asset already exists: ${candidate_dist_archive}"
dist_archive="${candidate_dist_archive}"
cp "${final_root}/slopwake-notarized.zip" "${dist_archive}"
release_complete=true

echo "notarization accepted: ${submission_id}"
echo "notarized app: ${final_root}/slopwake.app"
echo "notarized archive: ${dist_archive}"
