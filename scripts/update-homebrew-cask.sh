#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
archive="${2:-}"
tap_root="${3:-}"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: cask version must be a stable semantic version" >&2
  exit 1
}
[[ -f "${archive}" ]] || {
  echo "error: release archive does not exist: ${archive}" >&2
  exit 1
}
[[ -d "${tap_root}/.git" ]] || {
  echo "error: tap checkout does not exist: ${tap_root}" >&2
  exit 1
}

checksum="$(shasum -a 256 "${archive}" | awk '{print $1}')"
cask="${tap_root}/Casks/slopwake.rb"
mkdir -p "${tap_root}/Casks"
{
  echo 'cask "slopwake" do'
  echo "  version \"${version}\""
  echo "  sha256 \"${checksum}\""
  echo
  echo '  url "https://github.com/uinaf/slopwake/releases/download/v#{version}/slopwake-#{version}-macos-universal.zip"'
  echo '  name "slopwake"'
  echo '  desc "Keep your Mac awake while supported coding agents work"'
  echo '  homepage "https://github.com/uinaf/slopwake"'
  echo
  echo '  livecheck do'
  echo '    url :url'
  echo '    strategy :github_latest'
  echo '  end'
  echo
  echo '  depends_on macos: ">= :tahoe"'
  echo
  echo '  app "slopwake.app"'
  echo
  echo '  uninstall quit: "dev.uinaf.slopwake"'
  echo
  echo '  zap trash: "~/Library/Preferences/dev.uinaf.slopwake.plist"'
  echo 'end'
} >"${cask}"

echo "slopwake cask: ${cask}"
