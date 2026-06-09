#!/bin/sh
set -eu

tries="${1:-50}"
sleep_s="${2:-0.5}"

if [ "${EAP_ENABLE_VITAL:-0}" != "1" ]; then
    echo "Vitalium JACK wiring disabled; set EAP_ENABLE_VITAL=1 to connect it."
    exit 0
fi

if ! command -v jack_lsp >/dev/null 2>&1 || ! command -v jack_connect >/dev/null 2>&1; then
    echo "jack_lsp and jack_connect are required for Vital JACK wiring" >&2
    exit 1
fi

if command -v a2jmidid >/dev/null 2>&1 && ! pgrep -x a2jmidid >/dev/null 2>&1; then
    a2jmidid >/tmp/eap-a2jmidid.log 2>&1 &
    sleep 0.5
fi

i=0
while [ "$i" -lt "$tries" ]; do
    vital_l="$(jack_lsp | awk '{ line=tolower($0); if (line ~ /vital.*:.*audio.*out.*1$/) { print; exit } }')"
    vital_r="$(jack_lsp | awk '{ line=tolower($0); if (line ~ /vital.*:.*audio.*out.*2$/) { print; exit } }')"
    vital_midi="$(jack_lsp | awk '{ line=tolower($0); if (line ~ /vital.*:.*events.*in$/) { print; exit } }')"
    sc_midi="$(jack_lsp | awk '{ line=tolower($0); if (line ~ /supercollider.*capture.*out0/) { print; exit } }')"
    sc_l="$(jack_lsp | awk '/^SuperCollider:in_5$/ { print; exit }')"
    sc_r="$(jack_lsp | awk '/^SuperCollider:in_6$/ { print; exit }')"
    if [ -n "$vital_l" ] && [ -n "$vital_r" ] && [ -n "$sc_l" ] && [ -n "$sc_r" ]; then
        jack_disconnect "$vital_l" system:playback_1 2>/dev/null || true
        jack_disconnect "$vital_r" system:playback_2 2>/dev/null || true
        jack_disconnect "$vital_l" SuperCollider:in_3 2>/dev/null || true
        jack_disconnect "$vital_r" SuperCollider:in_4 2>/dev/null || true
        jack_connect "$vital_l" "$sc_l" 2>/dev/null || true
        jack_connect "$vital_r" "$sc_r" 2>/dev/null || true
        if [ -n "$vital_midi" ] && [ -n "$sc_midi" ]; then
            jack_connect "$sc_midi" "$vital_midi" 2>/dev/null || true
            echo "connected Vital JACK outs to SuperCollider inputs 5/6 and SuperCollider MIDI to Vital"
            exit 0
        fi
    fi
    i=$((i + 1))
    sleep "$sleep_s"
done

echo "Vital, SuperCollider, or bridged MIDI JACK ports were not found" >&2
exit 1
