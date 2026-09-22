#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_home="$(/usr/bin/mktemp -d /tmp/traceflow-codex-e2e.XXXXXX)"
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

notifier="$repo_root/.build/release/traceflow-notify"
command="/usr/bin/env TRACEFLOW_HOME=$test_home $notifier"
quoted_command="$(/usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$command")"
async_handler="{type=\"command\",command=$quoted_command,timeout=3,async=true}"
sync_handler="{type=\"command\",command=$quoted_command,timeout=3}"

codex exec --dangerously-bypass-hook-trust -C "$repo_root" \
    -c "hooks.SessionStart=[{matcher=\"startup|resume|clear\",hooks=[$async_handler]}]" \
    -c "hooks.UserPromptSubmit=[{hooks=[$async_handler]}]" \
    -c "hooks.PreToolUse=[{hooks=[$sync_handler]}]" \
    -c "hooks.Stop=[{hooks=[$sync_handler]}]" \
    -c "hooks.SessionEnd=[{hooks=[$sync_handler]}]" \
    "只回复：Traceflow 成品闭环通过。不要调用任何工具。" >/dev/null

sessions="$test_home/Library/Application Support/Traceflow/sessions.json"
attempt=0
while [ ! -f "$sessions" ] && [ "$attempt" -lt 50 ]; do /bin/sleep 0.1; attempt=$((attempt + 1)); done
/usr/bin/python3 -c '
import json, sys
document = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(document["sessions"]) == 1
session = document["sessions"][0]
assert session["projectName"] == "traceflow"
assert session["isIncludedInHUD"] is False
print("Traceflow Codex CLI E2E passed")
' "$sessions"
