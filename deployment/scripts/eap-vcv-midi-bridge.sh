#!/bin/sh
# Route SuperCollider ALSA MIDI (a2jmidid) into Midi Through where VCV Rack listens.
set -eu

if [ "${EAP_ENABLE_VCV:-0}" != "1" ]; then
    exit 0
fi

if ! command -v aconnect >/dev/null 2>&1; then
    echo "aconnect is required for VCV ALSA MIDI bridge" >&2
    exit 1
fi

if command -v a2jmidid >/dev/null 2>&1 && ! pgrep -x a2jmidid >/dev/null 2>&1; then
    a2jmidid >/tmp/eap-a2jmidid.log 2>&1 &
    sleep 0.5
fi

tries="${1:-40}"
sleep_s="${2:-0.5}"
through_port="${EAP_VCV_MIDI_DEVICE:-14:0}"

if aconnect -l 2>/dev/null | grep -q "Connected From: 131:0"; then
    echo "SuperCollider MIDI already routed to Midi Through (131:0 -> $through_port)"
    exit 0
fi

i=0
while [ "$i" -lt "$tries" ]; do
    sc_out="$(aconnect -l 2>/dev/null | awk '
        /client [0-9]+: .a2jmidid/ { client=$2; gsub(":", "", client); print client ":0"; exit }
    ')"
    if [ -z "$sc_out" ]; then
        sc_out="$(aconnect -l 2>/dev/null | awk '
            /client [0-9]+: .SuperCollider/ { client=$2; gsub(":", "", client); print client ":0"; exit }
        ')"
    fi
    if [ -n "$sc_out" ]; then
        aconnect "$sc_out" "$through_port" 2>/dev/null || true
        echo "connected ALSA MIDI $sc_out -> $through_port"
        exit 0
    fi
    i=$((i + 1))
    sleep "$sleep_s"
done

echo "VCV Rack ALSA MIDI bridge could not find SuperCollider MIDI output (dest=$through_port)" >&2
exit 1
