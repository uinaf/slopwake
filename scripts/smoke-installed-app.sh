#!/usr/bin/env bash
set -euo pipefail

app="${1:-/Applications/slopwake.app}"
[[ -d "${app}" ]] || {
  echo "error: installed app does not exist: ${app}" >&2
  exit 1
}

smoke_root="$(mktemp -d)"
app_pid=""
agent_pid=""
cleanup() {
  if [[ -n "${agent_pid}" ]]; then
    kill "${agent_pid}" 2>/dev/null || true
    wait "${agent_pid}" 2>/dev/null || true
  fi
  if [[ -n "${app_pid}" ]] && kill -0 "${app_pid}" 2>/dev/null; then
    osascript -e 'tell application id "dev.uinaf.slopwake" to quit' >/dev/null 2>&1 || true
  fi
  rm -rf "${smoke_root}"
}
trap cleanup EXIT

printf '#include <unistd.h>\nint main(void) { sleep(120); return 0; }\n' |
  xcrun clang -x c - -o "${smoke_root}/codex"
codesign --force --sign - "${smoke_root}/codex" >/dev/null
"${smoke_root}/codex" 120 &
agent_pid=$!
kill -0 "${agent_pid}"
[[ "$(basename "$(ps -p "${agent_pid}" -o comm= | xargs)")" == "codex" ]] || {
  echo "error: smoke agent did not expose the codex process name" >&2
  exit 1
}
open -n "${app}"

for attempt in {1..15}; do
  app_pid="$(pgrep -n -x slopwake || true)"
  [[ -n "${app_pid}" ]] && break
  sleep 1
done
[[ -n "${app_pid}" ]] || {
  echo "error: installed app did not launch" >&2
  exit 1
}

hold_pid=""
for attempt in {1..15}; do
  hold_pid="$(ps -axo pid=,ppid=,command= | awk -v app_pid="${app_pid}" '$2 == app_pid && $3 == "/usr/bin/caffeinate" { print $1 }')"
  [[ -n "${hold_pid}" ]] && break
  sleep 1
done
[[ -n "${hold_pid}" ]] || {
  echo "error: installed app did not create its owned wake hold" >&2
  exit 1
}
assertions="$(pmset -g assertions)"
grep -q "pid ${hold_pid}(caffeinate)" <<<"${assertions}" || {
  echo "error: pmset did not report the owned wake assertion" >&2
  exit 1
}

osascript -e 'tell application id "dev.uinaf.slopwake" to quit'
for attempt in {1..10}; do
  ! kill -0 "${app_pid}" 2>/dev/null && break
  sleep 1
done
if kill -0 "${app_pid}" 2>/dev/null; then
  echo "error: installed app did not quit" >&2
  exit 1
fi
if kill -0 "${hold_pid}" 2>/dev/null; then
  echo "error: installed app left its wake hold running" >&2
  exit 1
fi
assertions="$(pmset -g assertions)"
if grep -q "pid ${hold_pid}(caffeinate)" <<<"${assertions}"; then
  echo "error: pmset retained the released wake assertion" >&2
  exit 1
fi

echo "installed app launched, held wake, and quit cleanly"
