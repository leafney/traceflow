#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
capture_script="$repo_root/scripts/poc/capture-hook.sh"
output_path="${TRACEFLOW_POC_OUTPUT:-/tmp/traceflow-hooks-poc.jsonl}"

/bin/rm -f "$output_path"

escaped_command="$(/usr/bin/python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$capture_script")"
async_handler="{type=\"command\",command=$escaped_command,timeout=3,async=true}"
sync_handler="{type=\"command\",command=$escaped_command,timeout=3}"

TRACEFLOW_POC_OUTPUT="$output_path" codex exec \
    --dangerously-bypass-hook-trust \
    -C "$repo_root" \
    -c "hooks.SessionStart=[{matcher=\"startup|resume|clear\",hooks=[$async_handler]}]" \
    -c "hooks.UserPromptSubmit=[{hooks=[$async_handler]}]" \
    -c "hooks.PreToolUse=[{hooks=[$sync_handler]}]" \
    -c "hooks.PermissionRequest=[{hooks=[$async_handler]}]" \
    -c "hooks.PostToolUse=[{hooks=[$async_handler]}]" \
    -c "hooks.Stop=[{hooks=[$sync_handler]}]" \
    -c "hooks.Interrupt=[{hooks=[$async_handler]}]" \
    -c "hooks.SessionEnd=[{hooks=[$sync_handler]}]" \
    "只回复：Traceflow Hooks PoC。不要调用任何工具。"

# Background hooks may finish just after the command exits.
/bin/sleep 1
/bin/cat "$output_path"
