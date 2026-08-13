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
grep -Fq 'gh api --paginate --slurp "repos/${GITHUB_REPOSITORY}/releases?per_page=100"' .github/workflows/ci.yml
grep -Fq 'gh api "repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}"' .github/workflows/ci.yml
grep -Fq 'workflow_dispatch:' .github/workflows/ci.yml
grep -Fq 'cp homebrew-tap/Casks/slopwake.rb "${tap_root}/Casks/slopwake.rb"' .github/workflows/ci.yml
grep -Fq 'brew audit --online --strict --cask uinaf/tap/slopwake' .github/workflows/ci.yml
grep -Fq 'app-key: ${{ secrets.UINAF_RELEASE_APP_PRIVATE_KEY }}' .github/workflows/ci.yml

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
