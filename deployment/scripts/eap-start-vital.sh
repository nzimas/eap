#!/usr/bin/env bash
set -euo pipefail

state_dir="${EAP_VITAL_STATE_DIR:-/home/we/.local/share/eap-vital}"
controls_file="${1:-$state_dir/current.controls}"
pid_file="$state_dir/vital.pid"
log_file="$state_dir/vital.log"
cmd_fifo="$state_dir/vital.cmd"
client_name="${EAP_VITAL_JACK_NAME:-eap-vital}"
plugin_uri="${EAP_VITAL_LV2_URI:-urn:distrho:vitalium}"

mkdir -p "$state_dir"
touch "$controls_file"

if [[ "${EAP_ENABLE_VITAL:-0}" != "1" ]]; then
    echo "Vitalium realtime engine disabled; set EAP_ENABLE_VITAL=1 to launch it."
    exit 0
fi

if ! command -v jalv >/dev/null 2>&1; then
    echo "jalv is required to host the installed realtime Vitalium LV2 plugin." >&2
    exit 2
fi
if ! lv2ls | grep -qx "$plugin_uri"; then
    echo "Vitalium LV2 plugin is not installed or not visible to lv2ls: $plugin_uri" >&2
    exit 3
fi

if [[ -f "$pid_file" ]]; then
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
        pkill -TERM -P "$old_pid" 2>/dev/null || true
        kill "$old_pid" 2>/dev/null || true
        sleep 0.4
    fi
fi
rm -f "$cmd_fifo"
mkfifo "$cmd_fifo"

export HOME="${HOME:-/home/we}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export JACK_NO_AUDIO_RESERVATION=1

preset_uri=""
args=(-n "$client_name")
control_args=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    control_args+=(-c "$line")
done < "$controls_file"

if grep -q '^# preset_uri=' "$controls_file"; then
    preset_uri="$(sed -n 's/^# preset_uri=//p' "$controls_file" | sed -n '1p')"
fi

if [[ -n "$preset_uri" ]]; then
    nohup bash -c '
        controls_file="$1"
        preset_uri="$2"
        cmd_fifo="$3"
        shift 3
        {
            printf "preset %s\n" "$preset_uri"
            while IFS= read -r line; do
                [[ -z "$line" || "$line" == \#* ]] && continue
                printf "set %s %s\n" "${line%%=*}" "${line#*=}"
            done < "$controls_file"
            while true; do
                cat "$cmd_fifo"
                sleep 0.05
            done
        } | exec jalv "$@"
    ' _ "$controls_file" "$preset_uri" "$cmd_fifo" "${args[@]}" "$plugin_uri" >"$log_file" 2>&1 &
else
    nohup bash -c '
        cmd_fifo="$1"
        shift
        {
            while true; do
                cat "$cmd_fifo"
                sleep 0.05
            done
        } | exec jalv "$@"
    ' _ "$cmd_fifo" "${args[@]}" "${control_args[@]}" "$plugin_uri" >"$log_file" 2>&1 &
fi
pid="$!"
echo "$pid" > "$pid_file"
echo "started Vitalium realtime LV2 engine pid=$pid controls=$controls_file"
