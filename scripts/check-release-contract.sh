#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

bash -n scripts/*.sh
[[ -x scripts/install.sh ]] || {
  echo "error: scripts/install.sh must be executable" >&2
  exit 1
}
install_help="$(scripts/install.sh --help)"
grep -Fq -- '--version VERSION' <<<"${install_help}"
grep -Fq -- '--install-dir DIRECTORY' <<<"${install_help}"
grep -Fq -- '--force' <<<"${install_help}"
grep -Fq 'https://raw.githubusercontent.com/uinaf/slopwake/main/scripts/install.sh' README.md
grep -Fq '| bash -s -- --help' README.md
awk '
  index($0, "chmod -R u+rwX,go+rX,go-w \"$staged_app\"") { normalized = NR }
  index($0, "codesign --verify --deep --strict --verbose=2 \"$staged_app\"") { signed = NR }
  index($0, "spctl --assess --type execute --verbose=2 \"$staged_app\"") { assessed = NR }
  index($0, "mv \"$staged_app\" \"$target_app\"") { replaced = NR }
  END {
    if (normalized > 0 && signed > normalized && assessed > signed && replaced > assessed) exit 0
    print "installer must normalize, revalidate, and replace the staged app in order" > "/dev/stderr"
    exit 1
  }
' scripts/install.sh
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
grep -Fq 'gh release view "${RELEASE_TAG}" --json databaseId,isDraft' .github/workflows/ci.yml
grep -Fq 'release ${RELEASE_TAG} did not become visible after ${attempt} attempts' .github/workflows/ci.yml
if grep -Fq 'echo "draft=false"' .github/workflows/ci.yml; then
  echo "release discovery must fail closed when an expected draft is not visible" >&2
  exit 1
fi
grep -Fq 'gh api "repos/${GITHUB_REPOSITORY}/releases/${RELEASE_ID}"' .github/workflows/ci.yml
grep -Fq 'workflow_dispatch:' .github/workflows/ci.yml
grep -Fq 'group: verify-${{ github.workflow }}-${{ github.event_name }}-${{ github.ref }}' .github/workflows/ci.yml
grep -Fq "github.event_name != 'workflow_dispatch'" .github/workflows/ci.yml
grep -Fq 'cp homebrew-tap/Casks/slopwake.rb "${tap_root}/Casks/slopwake.rb"' .github/workflows/ci.yml
grep -Fq 'brew audit --online --strict --cask uinaf/tap/slopwake' .github/workflows/ci.yml
grep -Fq 'app-key: ${{ secrets.UINAF_RELEASE_APP_PRIVATE_KEY }}' .github/workflows/ci.yml
grep -Fq 'HOMEBREW_NO_AUTO_UPDATE: 1' .github/workflows/ci.yml
grep -Fq '"${app}/Contents/MacOS/slopwake" &' scripts/smoke-installed-app.sh

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
