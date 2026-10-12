#!/bin/sh
# Sourced by the installer. Command wrappers let tests simulate LaunchServices.
traceflow_launch_open() { /usr/bin/open "$1"; }
traceflow_launch_sleep() { /bin/sleep "$1"; }
traceflow_launch_processes() { /bin/ps -axo pid=,comm=; }

traceflow_launch_pids() {
    if ! traceflow_process_list="$(traceflow_launch_processes)"; then
        /usr/bin/printf '%s\n' '无法检查应用进程。' >&2
        return 2
    fi
    # Preserve the complete executable path, including spaces in the install directory.
    /usr/bin/printf '%s\n' "$traceflow_process_list" | /usr/bin/awk -v executable="$1/Contents/MacOS/Traceflow" '
        { pid = $1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == executable) print pid }
    '
}

traceflow_launch_app() {
    traceflow_app="$1"
    traceflow_launch_attempt=0
    while [ "$traceflow_launch_attempt" -lt 3 ]; do
        if ! traceflow_pids="$(traceflow_launch_pids "$traceflow_app")"; then return 1; fi
        if [ -n "$traceflow_pids" ]; then break; fi
        traceflow_launch_attempt=$((traceflow_launch_attempt + 1))
        if traceflow_open_message="$(traceflow_launch_open "$traceflow_app" 2>&1)"; then
            break
        fi
        /usr/bin/printf '%s\n' "$traceflow_open_message" >&2
        case "$traceflow_open_message" in
            *Code=-600*|*procNotFound*)
                if [ "$traceflow_launch_attempt" -ge 3 ]; then
                    /usr/bin/printf '%s\n' '应用已安装，但启动重试失败。请稍后手动打开。' >&2
                    return 1
                fi
                /usr/bin/printf '%s\n' '系统尚未完成旧进程的退出登记，稍后重试启动…' >&2
                traceflow_launch_sleep 0.5
                ;;
            *)
                /usr/bin/printf '%s\n' '应用已安装，但启动失败。' >&2
                return 1
                ;;
        esac
    done

    # A successful open only means the request was accepted. Wait for the exact
    # installed executable, then confirm the same process survives another sample.
    traceflow_poll=0
    while [ "$traceflow_poll" -lt 20 ]; do
        if ! traceflow_pids="$(traceflow_launch_pids "$traceflow_app")"; then return 1; fi
        if [ -n "$traceflow_pids" ]; then
            traceflow_launch_sleep 0.5
            if ! traceflow_next_pids="$(traceflow_launch_pids "$traceflow_app")"; then return 1; fi
            for traceflow_pid in $traceflow_pids; do
                for traceflow_next_pid in $traceflow_next_pids; do
                    if [ "$traceflow_pid" = "$traceflow_next_pid" ]; then return 0; fi
                done
            done
            /usr/bin/printf '%s\n' '应用已安装，但启动后进程立即退出，请检查崩溃记录。' >&2
            return 1
        fi
        traceflow_launch_sleep 0.25
        traceflow_poll=$((traceflow_poll + 1))
    done
    /usr/bin/printf '%s\n' '应用已安装，但等待启动进程超时。请稍后手动打开。' >&2
    return 1
}
