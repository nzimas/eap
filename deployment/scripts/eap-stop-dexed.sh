#!/usr/bin/env bash
set -euo pipefail

state_dir="${EAP_DEXED_STATE_DIR:-/home/we/.local/share/eap-dexed}"
pid_file="$state_dir/dexed.pid"
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
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    kill_pid "$pid"
fi

for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    cmdline="$(cmdline_of "$pid")"
    comm="$(comm_of "$pid")"
    if [[ ( "$comm" == "xvfb-run" && "$cmdline" == *"xvfb-run -a /usr/local/bin/Dexed"* ) ||
          ( "$comm" == "Dexed" && "$cmdline" == *"/usr/local/bin/Dexed"* ) ||
          ( "$comm" == "Xvfb" && "$cmdline" == Xvfb*"xvfb-run"* ) ]]; then
        kill_pid "$pid"
    fi
done
sleep 0.2
for proc in /proc/[0-9]*; do
    pid="${proc##*/}"
    cmdline="$(cmdline_of "$pid")"
    comm="$(comm_of "$pid")"
    if [[ ( "$comm" == "xvfb-run" && "$cmdline" == *"xvfb-run -a /usr/local/bin/Dexed"* ) ||
          ( "$comm" == "Dexed" && "$cmdline" == *"/usr/local/bin/Dexed"* ) ||
          ( "$comm" == "Xvfb" && "$cmdline" == Xvfb*"xvfb-run"* ) ]]; then
        stopped=1
        kill -KILL "$pid" 2>/dev/null || true
    fi
done
rm -f "$pid_file"
if [[ "$stopped" == "1" ]]; then
    echo "dexed stopped"
fi
