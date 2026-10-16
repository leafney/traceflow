#!/bin/sh
set -eu
repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
. "$repo_root/scripts/launch-app.sh"
test_dir="$(/usr/bin/mktemp -d /tmp/traceflow-launch-test.XXXXXX)"
trap '/bin/rm -rf -- "$test_dir"' EXIT HUP INT TERM
test_app="$test_dir/With Spaces/Traceflow.app"

traceflow_launch_sleep() { :; }
traceflow_launch_open() {
    count="$(cat "$test_dir/open-count")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$test_dir/open-count"
    case "$scenario" in
        retry|delayed)
            if [ "$count" -eq 1 ]; then printf '%s\n' 'Code=-600 procNotFound' >&2; return 1; fi ;;
        exhausted) printf '%s\n' 'Code=-600 procNotFound' >&2; return 1 ;;
        permanent) printf '%s\n' 'Code=-10810 other error' >&2; return 1 ;;
    esac
}
traceflow_launch_processes() {
    count="$(cat "$test_dir/process-count")"
    count=$((count + 1))
    printf '%s\n' "$count" > "$test_dir/process-count"
    # A different build with the same name must never satisfy the check.
    printf '%s\n' '999 /other/Traceflow.app/Contents/MacOS/Traceflow'
    case "$scenario" in
        already) printf ' 123 %s/Contents/MacOS/Traceflow\n' "$test_app" ;;
        retry) if [ "$(cat "$test_dir/open-count")" -ge 2 ]; then printf ' 123 %s/Contents/MacOS/Traceflow\n' "$test_app"; fi ;;
        delayed) if [ "$count" -ge 5 ]; then printf ' 123 %s/Contents/MacOS/Traceflow\n' "$test_app"; fi ;;
        early_exit) if [ "$count" -eq 2 ]; then printf ' 123 %s/Contents/MacOS/Traceflow\n' "$test_app"; fi ;;
        replaced)
            if [ "$count" -eq 2 ]; then printf ' 123 %s/Contents/MacOS/Traceflow\n' "$test_app"; fi
            if [ "$count" -ge 3 ]; then printf ' 124 %s/Contents/MacOS/Traceflow\n' "$test_app"; fi ;;
        process_error) return 1 ;;
    esac
}

run_case() {
    scenario="$1"
    expected_status="$2"
    expected_opens="$3"
    printf '0\n' > "$test_dir/open-count"
    printf '0\n' > "$test_dir/process-count"
    actual_status=0
    traceflow_launch_app "$test_app" > "$test_dir/output" 2>&1 || actual_status=$?
    if [ "$actual_status" -ne "$expected_status" ] || [ "$(cat "$test_dir/open-count")" -ne "$expected_opens" ]; then
        printf '失败：%s\n' "$scenario" >&2
        cat "$test_dir/output" >&2
        exit 1
    fi
}
run_case retry 0 2
run_case delayed 0 2
run_case already 0 0
run_case exhausted 1 3
rg -q 'Code=-600' "$test_dir/output"
run_case permanent 1 1
rg -q 'Code=-10810' "$test_dir/output"
run_case early_exit 1 1
run_case replaced 1 1
run_case timeout 1 1
run_case process_error 1 0
printf '%s\n' '启动重试与进程验证测试通过：九种场景'
