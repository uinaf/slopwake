#!/usr/bin/env bash
set -euo pipefail

app="DerivedData/Build/Products/Release/slopwake.app"
binary="${app}/Contents/MacOS/slopwake"
defaults_domain="dev.uinaf.slopwake"

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
defaults_backup="${fixture_root}/preferences.plist"
had_defaults=false
if defaults export "${defaults_domain}" "${defaults_backup}" >/dev/null 2>&1; then
  had_defaults=true
fi
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
  if [[ -n "${app_pid}" ]]; then
    wait "${app_pid}" 2>/dev/null || true
  fi
  if kill -0 "${fixture_pid}" 2>/dev/null; then
    kill -TERM "${fixture_pid}"
  fi
  wait "${fixture_pid}" 2>/dev/null || true
  if [[ "${had_defaults}" == true ]]; then
    defaults import "${defaults_domain}" "${defaults_backup}" >/dev/null
  else
    defaults delete "${defaults_domain}" >/dev/null 2>&1 || true
  fi
  rm -rf "${fixture_root}"
}
trap cleanup EXIT

launch_and_assert() {
  local prevent_display_sleep="$1"
  local expected_display_assertions="$2"

  defaults write "${defaults_domain}" prevents-display-sleep -bool "${prevent_display_sleep}"
  "${binary}" &
  app_pid=$!
  if ! kill -0 "${app_pid}" 2>/dev/null; then
    echo "error: slopwake.app exited during launch" >&2
    exit 1
  fi

  local caffeinate_deadline=$((SECONDS + 10))
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

  local assertions=""
  local base_assertion_count=0
  local display_assertion_count=0
  local assertion_deadline=$((SECONDS + 10))
  while ((SECONDS < assertion_deadline)); do
    assertions="$(pmset -g assertions)"
    base_assertion_count="$(
      grep "pid ${caffeinate_pid}(caffeinate)" <<<"${assertions}" |
        grep -Ec 'Prevent(DiskIdle|SystemSleep|UserIdleSystemSleep)' || true
    )"
    display_assertion_count="$(
      grep "pid ${caffeinate_pid}(caffeinate)" <<<"${assertions}" |
        grep -c 'PreventUserIdleDisplaySleep' || true
    )"
    if [[ "${base_assertion_count}" == 3 ]] &&
      [[ "${display_assertion_count}" == "${expected_display_assertions}" ]]; then
      break
    fi
    sleep 0.05
  done
  if [[ "${base_assertion_count}" != 3 ]]; then
    echo "error: expected three base power assertions, found ${base_assertion_count}" >&2
    exit 1
  fi
  if [[ "${display_assertion_count}" != "${expected_display_assertions}" ]]; then
    echo "error: expected ${expected_display_assertions} display assertions, found ${display_assertion_count}" >&2
    exit 1
  fi

  terminate_app
  local termination_deadline=$((SECONDS + 10))
  while ((SECONDS < termination_deadline)); do
    kill -0 "${app_pid}" 2>/dev/null || break
    sleep 0.01
  done
  if kill -0 "${app_pid}" 2>/dev/null; then
    echo "error: slopwake did not terminate" >&2
    exit 1
  fi
  wait "${app_pid}" 2>/dev/null || true

  local caffeinate_exit_deadline=$((SECONDS + 10))
  while ((SECONDS < caffeinate_exit_deadline)); do
    kill -0 "${caffeinate_pid}" 2>/dev/null || break
    sleep 0.01
  done
  if kill -0 "${caffeinate_pid}" 2>/dev/null; then
    echo "error: automatic caffeinate survived app termination" >&2
    exit 1
  fi
  app_pid=""
  caffeinate_pid=""
}

launch_and_assert false 0
launch_and_assert true 1
