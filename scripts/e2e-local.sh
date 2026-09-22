#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_home="$(/usr/bin/mktemp -d /tmp/traceflow-e2e.XXXXXX)"
app_pid=""
cleanup() {
    if [ -n "$app_pid" ]; then /bin/kill "$app_pid" 2>/dev/null || true; fi
    /bin/rm -rf "$test_home"
}
trap cleanup EXIT INT TERM

cd "$repo_root"
module_cache="$test_home/module-cache"
/bin/mkdir -p "$module_cache"
SWIFTPM_MODULECACHE_OVERRIDE="$module_cache" CLANG_MODULE_CACHE_PATH="$module_cache" swift build -c release >/dev/null
TRACEFLOW_HOME="$test_home" .build/release/Traceflow &
app_pid="$!"

socket="$test_home/Library/Application Support/Traceflow/traceflow.sock"
attempt=0
while [ ! -S "$socket" ] && [ "$attempt" -lt 50 ]; do /bin/sleep 0.1; attempt=$((attempt + 1)); done
[ -S "$socket" ]

send_event() {
    /usr/bin/printf '%s' "$1" | TRACEFLOW_HOME="$test_home" .build/release/traceflow-notify >/dev/null
}

send_event '{"session_id":"e2e-session","cwd":"/tmp/traceflow-demo","hook_event_name":"UserPromptSubmit","turn_id":"turn-1","prompt":"实现本地闭环"}'
send_event '{"session_id":"e2e-session","cwd":"/tmp/traceflow-demo","hook_event_name":"PermissionRequest","turn_id":"turn-1"}'
send_event '{"session_id":"e2e-session","cwd":"/tmp/traceflow-demo","hook_event_name":"Stop","turn_id":"turn-1"}'
send_event '{"session_id":"e2e-session","cwd":"/tmp/traceflow-demo","hook_event_name":"SessionEnd","turn_id":"turn-1"}'

sessions="$test_home/Library/Application Support/Traceflow/sessions.json"
attempt=0
while [ ! -f "$sessions" ] && [ "$attempt" -lt 50 ]; do /bin/sleep 0.1; attempt=$((attempt + 1)); done
/usr/bin/python3 -c '
import json, sys
document = json.load(open(sys.argv[1], encoding="utf-8"))
session = document["sessions"][0]
assert session["sessionID"] == "e2e-session"
assert session["projectName"] == "traceflow-demo"
assert session["isIncludedInHUD"] is False
assert "settingsListSortAt" in session
assert "conversationSummary" not in session
' "$sessions"

log="$test_home/Library/Logs/Traceflow/traceflow.log"
attempt=0
while [ ! -f "$log" ] && [ "$attempt" -lt 50 ]; do /bin/sleep 0.1; attempt=$((attempt + 1)); done
[ -f "$log" ]
/usr/bin/grep -q 'event=UserPromptSubmit state=idle->running' "$log"
/usr/bin/grep -q 'event=PermissionRequest state=running->attention' "$log"
/usr/bin/grep -q 'event=Stop state=attention->completed' "$log"
/usr/bin/grep -q 'event=SessionEnd state=completed->idle' "$log"
/usr/bin/printf '%s\n' 'Traceflow 本地状态序列端到端验证通过'
