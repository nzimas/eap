#!/bin/sh
set -eu

tries="${1:-60}"
sleep_s="${2:-0.5}"

if ! command -v jack_connect >/dev/null 2>&1; then
    echo "jack_connect is required" >&2
    exit 1
fi

disconnect_sc_self_loops() {
    for out in SuperCollider:out_1 SuperCollider:out_2 SuperCollider:out_3 SuperCollider:out_4; do
        jack_disconnect "$out" system:playback_1 2>/dev/null || true
        jack_disconnect "$out" system:playback_2 2>/dev/null || true
        jack_disconnect "$out" SuperCollider:in_1 2>/dev/null || true
        jack_disconnect "$out" SuperCollider:in_2 2>/dev/null || true
        jack_disconnect "$out" SuperCollider:in_3 2>/dev/null || true
        jack_disconnect "$out" SuperCollider:in_4 2>/dev/null || true
        jack_disconnect "$out" system:capture_1 2>/dev/null || true
        jack_disconnect "$out" system:capture_2 2>/dev/null || true
    done
    for inp in SuperCollider:in_1 SuperCollider:in_2 SuperCollider:in_3 SuperCollider:in_4; do
        jack_disconnect system:capture_1 "$inp" 2>/dev/null || true
        jack_disconnect system:capture_2 "$inp" 2>/dev/null || true
    done
}

connect_once() {
    disconnect_sc_self_loops
    jack_connect SuperCollider:out_1 system:playback_1 2>/dev/null || true
    jack_connect SuperCollider:out_2 system:playback_2 2>/dev/null || true
}

i=0
while [ "$i" -lt "$tries" ]; do
    if jack_lsp 2>/dev/null | awk '/^SuperCollider:out_1$/ { found=1 } END { exit !found }'; then
        connect_once
        echo "EAP SuperCollider outputs connected to system playback"
        exit 0
    fi
    i=$((i + 1))
    sleep "$sleep_s"
done

echo "SuperCollider JACK output ports were not found" >&2
exit 1
