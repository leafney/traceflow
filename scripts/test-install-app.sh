#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
test_dir="$(/usr/bin/mktemp -d /tmp/traceflow-install-test.XXXXXX)"
trap '/bin/rm -rf -- "$test_dir"' EXIT HUP INT TERM

"$repo_root/scripts/build-app.sh"
install_dir="$test_dir/Applications"
/bin/mkdir -p "$install_dir"

TRACEFLOW_INSTALL_DIR="$install_dir" TRACEFLOW_SKIP_BUILD=1 TRACEFLOW_SKIP_LAUNCH=1 TRACEFLOW_SKIP_PROCESS_CHECK=1 "$repo_root/scripts/install-app.sh"
app="$install_dir/Traceflow.app"
[ -x "$app/Contents/MacOS/Traceflow" ]
[ -x "$app/Contents/MacOS/traceflow-notify" ]
[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$app/Contents/Info.plist")" = true ]
/usr/bin/codesign --verify "$app"

TRACEFLOW_INSTALL_DIR="$install_dir" TRACEFLOW_SKIP_BUILD=1 TRACEFLOW_SKIP_LAUNCH=1 TRACEFLOW_SKIP_PROCESS_CHECK=1 "$repo_root/scripts/install-app.sh"
[ -x "$app/Contents/MacOS/Traceflow" ]
[ -x "$app/Contents/MacOS/traceflow-notify" ]
[ "$(/usr/bin/plutil -extract LSUIElement raw -o - "$app/Contents/Info.plist")" = true ]
/usr/bin/codesign --verify "$app"

/usr/bin/printf '%s\n' 'Traceflow 安装与重复安装测试通过'
