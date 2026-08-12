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

app_pid=""
cleanup() {
  if [[ -n "${app_pid}" ]] && kill -0 "${app_pid}" 2>/dev/null; then
    kill -TERM "${app_pid}"
  fi
  if [[ -n "${app_pid}" ]]; then
    wait "${app_pid}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

"${binary}" &
app_pid=$!
sleep 1
app_state="$(ps -p "${app_pid}" -o state= 2>/dev/null | tr -d ' ' || true)"
if [[ -z "${app_state}" || "${app_state}" == Z* ]]; then
  echo "error: slopwake exited during launch" >&2
  exit 1
fi
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
wait "${app_pid}" 2>/dev/null || true
trap - EXIT
