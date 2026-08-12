#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n scripts/*.sh
ruby -rjson -e '
  config = JSON.parse(File.read(".releaserc.json"))
  plugins = config.fetch("plugins").flatten
  abort "expected @jno21/semantic-release-github-commit" unless plugins.include?("@jno21/semantic-release-github-commit")
  abort "unsigned @semantic-release/git writeback" if plugins.include?("@semantic-release/git")
'
ruby -ryaml -e '
  YAML.load_file(".github/workflows/ci.yml")
  YAML.load_file(".github/workflows/secrets.yml")
  YAML.load_file(".github/dependabot.yml")
'

version="$(sed -n '1p' VERSION)"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: VERSION must contain one stable semantic version" >&2
  exit 1
}
project_version="$(sed -n 's/^        MARKETING_VERSION: //p' project.yml)"
[[ "${project_version}" == "${version}" ]] || {
  echo "error: VERSION and project.yml MARKETING_VERSION differ" >&2
  exit 1
}

fixture_root="$(mktemp -d)"
trap 'rm -rf "${fixture_root}"' EXIT
tap_root="${fixture_root}/tap"
archive="${fixture_root}/slopwake-1.2.3-macos-universal.zip"
mkdir -p "${tap_root}"
git -C "${tap_root}" init -q
printf 'slopwake release fixture\n' >"${archive}"
scripts/update-homebrew-cask.sh 1.2.3 "${archive}" "${tap_root}" >/dev/null
ruby -c "${tap_root}/Casks/slopwake.rb" >/dev/null
expected_checksum="$(shasum -a 256 "${archive}" | awk '{print $1}')"
grep -q "sha256 \"${expected_checksum}\"" "${tap_root}/Casks/slopwake.rb"

echo "release contract ok"
