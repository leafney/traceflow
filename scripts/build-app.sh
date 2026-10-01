#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
output="$repo_root/dist/Traceflow.app"

cd "$repo_root"
if [ ! -s "$repo_root/packaging/Traceflow.icns" ]; then
    /usr/bin/printf '%s\n' '应用图标缺失或为空，请先执行 scripts/generate-app-icon.sh' >&2
    exit 1
fi
swift build -c release
/bin/rm -rf "$output"
/bin/mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
/bin/cp .build/release/Traceflow "$output/Contents/MacOS/Traceflow"
/bin/cp .build/release/traceflow-notify "$output/Contents/MacOS/traceflow-notify"
/bin/cp packaging/Info.plist "$output/Contents/Info.plist"
/bin/cp packaging/Traceflow.icns "$output/Contents/Resources/Traceflow.icns"
/usr/bin/plutil -lint "$output/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$output"
/usr/bin/printf '%s\n' "$output"
