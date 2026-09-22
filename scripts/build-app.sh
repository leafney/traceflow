#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
output="$repo_root/dist/Traceflow.app"

cd "$repo_root"
swift build -c release
/bin/rm -rf "$output"
/bin/mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
/bin/cp .build/release/Traceflow "$output/Contents/MacOS/Traceflow"
/bin/cp .build/release/traceflow-notify "$output/Contents/MacOS/traceflow-notify"
/bin/cp packaging/Info.plist "$output/Contents/Info.plist"
/usr/bin/plutil -lint "$output/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$output"
/usr/bin/printf '%s\n' "$output"
