#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

pinned_version="$(
  sed -n 's/^xcodegen_version="\(.*\)"$/\1/p' scripts/install-xcodegen.sh
)"
if [[ -z "${pinned_version}" ]]; then
  echo "error: scripts/install-xcodegen.sh has no pinned version." >&2
  exit 1
fi

pinned_root="${SLOPWAKE_XCODEGEN_ROOT:-.artifacts/toolchain/xcodegen-${pinned_version}}"
pinned_binary="${pinned_root}/xcodegen/bin/xcodegen"

if [[ ! -x "${pinned_binary}" ]]; then
  rm -rf "${pinned_root:?}/xcodegen"
  mkdir -p "${pinned_root}"
  ./scripts/install-xcodegen.sh "${pinned_root}" >/dev/null
fi

exec "${pinned_binary}" generate --spec project.yml
