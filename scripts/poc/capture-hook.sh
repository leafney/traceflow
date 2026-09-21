#!/bin/sh
set -eu

output_path="${TRACEFLOW_POC_OUTPUT:-/tmp/traceflow-hooks-poc.jsonl}"
payload="$(/bin/cat)"

/usr/bin/python3 -c '
import hashlib
import json
import sys
from datetime import datetime, timezone

output_path = sys.argv[1]
payload = json.loads(sys.argv[2])
session_id = str(payload.get("session_id", ""))
record = {
    "captured_at": datetime.now(timezone.utc).isoformat(),
    "event": payload.get("hook_event_name"),
    "session_hash": hashlib.sha256(session_id.encode()).hexdigest()[:12],
    "has_cwd": isinstance(payload.get("cwd"), str),
    "has_turn_id": isinstance(payload.get("turn_id"), str),
    "source": payload.get("source"),
    "keys": sorted(payload.keys()),
}
with open(output_path, "a", encoding="utf-8") as stream:
    stream.write(json.dumps(record, ensure_ascii=False) + "\n")
' "$output_path" "$payload"

# All observed events receive inert JSON. This hook never controls Codex.
/usr/bin/printf '{}\n'
