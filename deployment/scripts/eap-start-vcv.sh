#!/usr/bin/env bash
set -euo pipefail

state_dir="${EAP_VCV_STATE_DIR:-/home/we/.local/share/eap-vcv}"
patch_file="${1:-$state_dir/current.vcv}"
pid_file="$state_dir/vcv.pid"
log_file="$state_dir/vcv.log"
rack_bin="${EAP_RACK_BIN:-/usr/local/bin/eap-rack}"

mkdir -p "$state_dir"

if [[ "${EAP_ENABLE_VCV:-0}" != "1" ]]; then
    echo "VCV Rack realtime engine disabled; set EAP_ENABLE_VCV=1 to launch it."
    exit 0
fi

if [[ ! -x "$rack_bin" ]]; then
    echo "VCV Rack binary is not installed: $rack_bin" >&2
    exit 2
fi

if [[ ! -f "$patch_file" ]]; then
    echo "VCV Rack patch does not exist: $patch_file" >&2
    exit 3
fi

if [[ "${EAP_VCV_FOREGROUND:-0}" != "1" ]] && [[ -f "$pid_file" ]]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null || true
        sleep 0.5
    fi
fi

export HOME="${HOME:-/home/we}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export RACK_USER_DIR="${EAP_VCV_RACK_USER_DIR:-$state_dir/Rack2}"
export JACK_NO_AUDIO_RESERVATION=1

mkdir -p "$RACK_USER_DIR"
if [[ "${EAP_VCV_FOREGROUND:-0}" = "1" ]]; then
    echo "$$" > "$pid_file"
    exec "$rack_bin" -h "$patch_file"
else
    nohup "$rack_bin" -h "$patch_file" >"$log_file" 2>&1 &
    pid="$!"
    echo "$pid" > "$pid_file"
    echo "started VCV Rack headless engine pid=$pid patch=$patch_file"
fi
