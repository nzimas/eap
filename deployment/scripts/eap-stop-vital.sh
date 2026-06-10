#!/usr/bin/env bash
set -euo pipefail

state_dir="${EAP_VITAL_STATE_DIR:-/home/we/.local/share/eap-vital}"
pid_file="$state_dir/vital.pid"
cmd_fifo="$state_dir/vital.cmd"
stopped=0

kill_pid() {
    local pid="$1"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        stopped=1
        pkill -TERM -P "$pid" 2>/dev/null || true
        kill "$pid" 2>/dev/null || true
    fi
}

cmdline_of() {
    [[ -r "/proc/$1/cmdline" ]] || return 0
    tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null || true
}

comm_of() {
    [[ -r "/proc/$1/comm" ]] || return 0
    cat "/proc/$1/comm" 2>/dev/null || true
}

if [[ -f "$pid_file" ]]; then
    kill_pid "$(cat "$pid_file" 2>/dev/null || true)"
fi

for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    cmdline="$(cmdline_of "$pid")"
    comm="$(comm_of "$pid")"
    if [[ "$comm" == "jalv" && "$cmdline" == *"jalv -n eap-vital"* ]]; then
        kill_pid "$pid"
    fi
done

if [[ -n "$cmd_fifo" ]]; then
    for proc in /proc/[0-9]*; do
        pid="${proc##*/}"
        [[ "$pid" == "$$" || "$pid" == "$PPID" ]] && continue
        cmdline="$(cmdline_of "$pid")"
        [[ "$(comm_of "$pid")" == "cat" ]] || continue
        [[ "$cmdline" == "cat $cmd_fifo "* || "$cmdline" == "cat $cmd_fifo" ]] || continue
        kill_pid "$pid"
    done
fi

sleep 0.2

for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    cmdline="$(cmdline_of "$pid")"
    comm="$(comm_of "$pid")"
    if [[ "$comm" == "jalv" && "$cmdline" == *"jalv -n eap-vital"* ]]; then
        stopped=1
        kill -KILL "$pid" 2>/dev/null || true
    fi
done

rm -f "$pid_file" "$cmd_fifo"
if [[ "$stopped" == "1" ]]; then
    echo "vital stopped"
fi
