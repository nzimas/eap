#!/usr/bin/env bash
set -euo pipefail

tries="${1:-25}"
sleep_s="${2:-0.25}"
state_dir="${EAP_DEXED_STATE_DIR:-/home/we/.local/share/eap-dexed}"
log_file="$state_dir/dexed.log"

mkdir -p "$state_dir"

have_ports() {
    jack_lsp 2>/dev/null | awk '
        BEGIN { left=0; right=0 }
        /^[Dd]exed:out_?1$/ || /^[Dd]exed:output_?1$/ || /^[Dd]exed:audio_out_?1$/ { left=1 }
        /^[Dd]exed:out_?2$/ || /^[Dd]exed:output_?2$/ || /^[Dd]exed:audio_out_?2$/ { right=1 }
        END { exit !(left && right) }
    '
}

if ! command -v /usr/local/bin/Dexed >/dev/null 2>&1; then
    echo "dexed binary missing"
    exit 0
fi

if ! have_ports; then
    pkill -TERM -f 'xvfb-run -a /usr/local/bin/Dexed|/usr/local/bin/Dexed' 2>/dev/null || true
    sleep 0.4
    nohup env EAP_ENABLE_DEXED=1 /usr/local/bin/eap-start-dexed >"$log_file" 2>&1 &
    echo "$!" >"$state_dir/dexed.pid"
fi

i=0
while [ "$i" -lt "$tries" ]; do
    if have_ports; then
        EAP_ENABLE_DEXED=1 /usr/local/bin/eap-connect-dexed-jack 12 0.15 >/dev/null 2>&1 || true
        echo "dexed ready"
        exit 0
    fi
    i=$((i + 1))
    sleep "$sleep_s"
done

EAP_ENABLE_DEXED=1 /usr/local/bin/eap-connect-dexed-jack 1 0.1 >/dev/null 2>&1 || true
echo "dexed requested; ports not visible yet"
exit 0
