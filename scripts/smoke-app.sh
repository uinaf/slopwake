#!/usr/bin/env bash
set -euo pipefail

app="DerivedData/Build/Products/Release/slopwake.app"
binary="${app}/Contents/MacOS/slopwake"

architectures="$(lipo -archs "${binary}")"
[[ " ${architectures} " == *" arm64 "* ]] || {
  echo "error: Release binary is missing arm64" >&2
  exit 1
}
[[ " ${architectures} " == *" x86_64 "* ]] || {
  echo "error: Release binary is missing x86_64" >&2
  exit 1
}

codesign --force --deep --sign - --options runtime "${app}"
codesign --verify --deep --strict --verbose=2 "${app}"
signature_details="$(codesign --display --verbose=4 "${app}" 2>&1)"
grep -q 'flags=.*runtime' <<<"${signature_details}"

if pgrep -x slopwake >/dev/null; then
  echo "error: another slopwake process is already running" >&2
  exit 1
fi

open -n "${app}"
app_pid=""
launch_deadline=$((SECONDS + 10))
while ((SECONDS < launch_deadline)); do
  app_pid="$(pgrep -x slopwake || true)"
  [[ -n "${app_pid}" ]] && break
  sleep 0.01
done
if [[ -z "${app_pid}" ]]; then
  echo "error: LaunchServices did not launch slopwake.app" >&2
  exit 1
fi

cleanup() {
  if kill -0 "${app_pid}" 2>/dev/null; then
    kill -TERM "${app_pid}"
  fi
}
trap cleanup EXIT

kill -0 "${app_pid}"
kill -TERM "${app_pid}"
termination_deadline=$((SECONDS + 10))
while ((SECONDS < termination_deadline)); do
  kill -0 "${app_pid}" 2>/dev/null || break
  sleep 0.01
done

if kill -0 "${app_pid}" 2>/dev/null; then
  echo "error: slopwake did not terminate" >&2
  exit 1
fi
trap - EXIT
