#!/bin/sh
set -eu

tries="${1:-40}"
sleep_s="${2:-0.5}"

if ! command -v jack_lsp >/dev/null 2>&1 || ! command -v jack_connect >/dev/null 2>&1; then
    echo "jack_lsp and jack_connect are required for Dexed JACK wiring" >&2
    exit 1
fi

i=0
while [ "$i" -lt "$tries" ]; do
    dexed_l="$(jack_lsp | awk '/^[Dd]exed:out_?1$/ || /^[Dd]exed:output_?1$/ || /^[Dd]exed:audio_out_?1$/ { print; exit }')"
    dexed_r="$(jack_lsp | awk '/^[Dd]exed:out_?2$/ || /^[Dd]exed:output_?2$/ || /^[Dd]exed:audio_out_?2$/ { print; exit }')"
    sc_l="$(jack_lsp | awk '/^SuperCollider:in_3$/ { print; exit }')"
    sc_r="$(jack_lsp | awk '/^SuperCollider:in_4$/ { print; exit }')"
    if [ -n "$dexed_l" ] && [ -n "$dexed_r" ] && [ -n "$sc_l" ] && [ -n "$sc_r" ]; then
        jack_disconnect "$dexed_l" system:playback_1 2>/dev/null || true
        jack_disconnect "$dexed_r" system:playback_2 2>/dev/null || true
        jack_connect "$dexed_l" "$sc_l" 2>/dev/null || true
        jack_connect "$dexed_r" "$sc_r" 2>/dev/null || true
        echo "connected Dexed JACK outs to SuperCollider inputs 3/4"
        exit 0
    fi
    i=$((i + 1))
    sleep "$sleep_s"
done

echo "Dexed or SuperCollider JACK ports were not found" >&2
exit 1
