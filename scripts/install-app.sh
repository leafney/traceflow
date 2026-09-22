#!/bin/sh
set -eu

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
source_app="$repo_root/dist/Traceflow.app"
install_dir="${TRACEFLOW_INSTALL_DIR:-/Applications}"
destination="$install_dir/Traceflow.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Installation tests use a private destination and skip launching the app.
case "$install_dir" in
    /*) ;;
    *) /usr/bin/printf '%s\n' '安装目录必须是绝对路径' >&2; exit 1 ;;
esac
if [ -L "$install_dir" ] || [ ! -d "$install_dir" ]; then
    /usr/bin/printf '%s\n' "安装目录不存在或是符号链接：$install_dir" >&2
    exit 1
fi
if [ -L "$destination" ]; then
    /usr/bin/printf '%s\n' "拒绝替换符号链接：$destination" >&2
    exit 1
fi

if [ "${TRACEFLOW_SKIP_BUILD:-0}" != 1 ]; then
    "$repo_root/scripts/build-app.sh"
fi
if [ ! -f "$source_app/Contents/Info.plist" ] || [ ! -x "$source_app/Contents/MacOS/Traceflow" ] || [ ! -x "$source_app/Contents/MacOS/traceflow-notify" ]; then
    /usr/bin/printf '%s\n' '构建产物不完整，未安装' >&2
    exit 1
fi
/usr/bin/plutil -lint "$source_app/Contents/Info.plist" >/dev/null
/usr/bin/codesign --verify "$source_app"

if [ -w "$install_dir" ]; then
    privileged() { "$@"; }
else
    /usr/bin/printf '%s\n' "安装到 $install_dir 需要管理员权限，接下来可能提示输入密码。"
    /usr/bin/sudo -v
    privileged() { /usr/bin/sudo "$@"; }
fi

stage="$(privileged /usr/bin/mktemp -d "$install_dir/.traceflow-install.XXXXXX")"
staged_app="$stage/Traceflow.app"
previous_app="$stage/Previous.app"
installed=0
cleanup() {
    if [ "$installed" -eq 0 ] && [ -d "$previous_app" ] && [ ! -e "$destination" ]; then
        privileged /bin/mv "$previous_app" "$destination" || true
    fi
    if [ -d "$stage" ]; then privileged /bin/rm -rf -- "$stage"; fi
}
trap cleanup EXIT HUP INT TERM

privileged /usr/bin/ditto "$source_app" "$staged_app"
privileged /usr/bin/plutil -lint "$staged_app/Contents/Info.plist" >/dev/null
privileged /usr/bin/codesign --verify "$staged_app"

if [ -d "$destination" ]; then
    # Only the exact installed executable is stopped; other builds remain untouched.
    running_pids=""
    if [ "${TRACEFLOW_SKIP_PROCESS_CHECK:-0}" != 1 ]; then
        if ! process_list="$(/bin/ps -axo pid=,comm=)"; then
            /usr/bin/printf '%s\n' '无法检查旧版进程，安装已取消。' >&2
            exit 1
        fi
        running_pids="$(/usr/bin/printf '%s\n' "$process_list" | /usr/bin/awk -v executable="$destination/Contents/MacOS/Traceflow" '$2 == executable { print $1 }')"
    fi
    if [ -n "$running_pids" ]; then
        /usr/bin/printf '%s\n' '正在退出旧版 Traceflow…'
        if ! /usr/bin/osascript -e 'tell application id "io.traceflow.app" to quit'; then
            /usr/bin/printf '%s\n' '无法正常退出旧版 Traceflow。请从菜单栏手动退出后重试。' >&2
            exit 1
        fi
        attempt=0
        while [ "$attempt" -lt 50 ]; do
            still_running=0
            for pid in $running_pids; do
                if /bin/kill -0 "$pid" 2>/dev/null; then still_running=1; fi
            done
            if [ "$still_running" -eq 0 ]; then break; fi
            /bin/sleep 0.1
            attempt=$((attempt + 1))
        done
        if [ "$still_running" -ne 0 ]; then
            /usr/bin/printf '%s\n' '旧版 Traceflow 未能退出，安装已取消。请先从菜单栏退出应用。' >&2
            exit 1
        fi
    fi
    privileged /bin/mv "$destination" "$previous_app"
fi

privileged /bin/mv "$staged_app" "$destination"
installed=1
privileged /bin/rm -rf -- "$stage"
trap - EXIT HUP INT TERM

if [ "${TRACEFLOW_SKIP_LAUNCH:-0}" != 1 ]; then
    "$lsregister" -f "$destination"
    /usr/bin/open "$destination"
fi
/usr/bin/printf '安装完成：%s\n' "$destination"
/usr/bin/printf '%s\n' '以后可从“应用程序”或 Spotlight 搜索 Traceflow 再次打开；运行时只有菜单栏图标，不显示 Dock 图标。'
