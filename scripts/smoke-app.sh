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

fixture_root="$(mktemp -d .artifacts/slopwake-smoke.XXXXXX)"
xcrun clang scripts/fixtures/headless-agent.c -o "${fixture_root}/codex"
"${fixture_root}/codex" &
fixture_pid=$!
app_pid=""
caffeinate_pid=""
terminate_app() {
  [[ -n "${app_pid}" ]] || return 0
  kill -0 "${app_pid}" 2>/dev/null || return 0
  if ! kill -TERM "${app_pid}" 2>/dev/null && kill -0 "${app_pid}" 2>/dev/null; then
    echo "error: could not terminate slopwake" >&2
    return 1
  fi
}
cleanup() {
  terminate_app
  if [[ -n "${app_pid}" ]]; then
    wait "${app_pid}" 2>/dev/null || true
  fi
  if kill -0 "${fixture_pid}" 2>/dev/null; then
    kill -TERM "${fixture_pid}"
  fi
  wait "${fixture_pid}" 2>/dev/null || true
  rm -rf "${fixture_root}"
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
caffeinate_deadline=$((SECONDS + 10))
while ((SECONDS < caffeinate_deadline)); do
  caffeinate_pid="$(pgrep -P "${app_pid}" caffeinate || true)"
  [[ -n "${caffeinate_pid}" ]] && break
  sleep 0.05
done
if [[ -z "${caffeinate_pid}" ]]; then
  echo "error: automatic detection did not start caffeinate" >&2
  exit 1
fi
if ! kill -0 "${fixture_pid}" 2>/dev/null; then
  echo "error: headless detector fixture exited before verification" >&2
  exit 1
fi

assertion_count="$(
  pmset -g assertions |
    grep "pid ${caffeinate_pid}(caffeinate)" |
    grep -Ec 'Prevent(DiskIdle|SystemSleep|UserIdleSystemSleep)' || true
)"
if [[ "${assertion_count}" != 3 ]]; then
  echo "error: expected three caffeinate power assertions, found ${assertion_count}" >&2
  exit 1
fi
terminate_app
termination_deadline=$((SECONDS + 10))
while ((SECONDS < termination_deadline)); do
  kill -0 "${app_pid}" 2>/dev/null || break
  sleep 0.01
done

if kill -0 "${app_pid}" 2>/dev/null; then
  echo "error: slopwake did not terminate" >&2
    exit 1
fi

caffeinate_exit_deadline=$((SECONDS + 10))
while ((SECONDS < caffeinate_exit_deadline)); do
  kill -0 "${caffeinate_pid}" 2>/dev/null || break
  sleep 0.01
done
if kill -0 "${caffeinate_pid}" 2>/dev/null; then
  echo "error: automatic caffeinate survived app termination" >&2
  exit 1
fi
wait "${app_pid}" 2>/dev/null || true
cleanup
trap - EXIT
