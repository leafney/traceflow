#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
icon_temp="$(/usr/bin/mktemp -d /tmp/traceflow-icon.XXXXXX)"
pending_resource=""
trap '[ -z "$pending_resource" ] || /bin/rm -f -- "$pending_resource"; /bin/rm -rf -- "$icon_temp"' EXIT HUP INT TERM
/bin/mkdir -p "$icon_temp/Traceflow.iconset" "$icon_temp/sources" "$icon_temp/module-cache"
/usr/bin/swiftc -module-cache-path "$icon_temp/module-cache" "$repo_root/scripts/generate-app-icon.swift" -o "$icon_temp/generate-icon"
"$icon_temp/generate-icon" --iconset "$icon_temp/Traceflow.iconset" --source-dir "$icon_temp/sources"
/usr/bin/iconutil -c icns "$icon_temp/Traceflow.iconset" -o "$icon_temp/sources/Traceflow.icns"

for resource in TraceflowIcon.svg TraceflowMenuIcon.svg Traceflow.icns; do
    [ -s "$icon_temp/sources/$resource" ] || { /usr/bin/printf '图标资源为空：%s\n' "$resource" >&2; exit 1; }
done
for resource in TraceflowIcon.svg TraceflowMenuIcon.svg Traceflow.icns; do
    pending_resource="$(/usr/bin/mktemp "$repo_root/packaging/.icon-resource.XXXXXX")"
    if ! /bin/cp "$icon_temp/sources/$resource" "$pending_resource" || ! /bin/chmod 644 "$pending_resource" || ! /bin/mv -f "$pending_resource" "$repo_root/packaging/$resource"; then
        /usr/bin/printf '无法替换图标资源：packaging/%s\n' "$resource" >&2
        exit 1
    fi
    pending_resource=""
done
/usr/bin/printf '%s\n' packaging/TraceflowIcon.svg packaging/TraceflowMenuIcon.svg packaging/Traceflow.icns
