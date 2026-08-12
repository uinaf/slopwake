#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
[[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "error: release version must be a stable semantic version" >&2
  exit 1
}

[[ "$(grep -c '^        MARKETING_VERSION:' project.yml)" == "1" ]] || {
  echo "error: project.yml must contain exactly one app marketing version" >&2
  exit 1
}
versioned_project="$(mktemp)"
trap 'rm -f "${versioned_project}"' EXIT
sed -E "s/^        MARKETING_VERSION: .*/        MARKETING_VERSION: ${version}/" project.yml >"${versioned_project}"
cp "${versioned_project}" project.yml
printf '%s\n' "${version}" >VERSION
