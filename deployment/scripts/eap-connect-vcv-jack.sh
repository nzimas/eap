#!/bin/sh
set -eu

tries="${1:-80}"
sleep_s="${2:-0.5}"

if [ "${EAP_ENABLE_VCV:-0}" != "1" ]; then
    echo "VCV Rack JACK wiring disabled; set EAP_ENABLE_VCV=1 to connect it."
    exit 0
fi

if ! command -v jack_lsp >/dev/null 2>&1 || ! command -v jack_connect >/dev/null 2>&1; then
    echo "jack_lsp and jack_connect are required for VCV JACK wiring" >&2
    exit 1
fi

if command -v a2jmidid >/dev/null 2>&1 && ! pgrep -x a2jmidid >/dev/null 2>&1; then
    a2jmidid >/tmp/eap-a2jmidid.log 2>&1 &
    sleep 0.5
fi

i=0
audio_ok=0
while [ "$i" -lt "$tries" ]; do
    vcv_l="$(jack_lsp | awk '{ line=tolower($0); if (line ~ /(rack|vcv).*:.*(audio|out).*(_| |-)1$/ || line ~ /(rack|vcv).*:.*outport 0$/ || line ~ /(rack|vcv).*:.*left$/) { print; exit } }')"
    vcv_r="$(jack_lsp | awk '{ line=tolower($0); if (line ~ /(rack|vcv).*:.*(audio|out).*(_| |-)2$/ || line ~ /(rack|vcv).*:.*outport 1$/ || line ~ /(rack|vcv).*:.*right$/) { print; exit } }')"
    vcv_midi="$(jack_lsp | awk '{ line=tolower($0); if (line ~ /(rack|vcv).*:.*(midi|event).*in/) { print; exit } }')"
    sc_midi="$(jack_lsp | awk '{ line=tolower($0); if (line ~ /supercollider.*capture.*out0/) { print; exit } }')"
    sc_l="$(jack_lsp | awk '/^SuperCollider:in_3$/ { print; exit }')"
    sc_r="$(jack_lsp | awk '/^SuperCollider:in_4$/ { print; exit }')"
    if [ -n "$vcv_l" ] && [ -n "$vcv_r" ] && [ -n "$sc_l" ] && [ -n "$sc_r" ]; then
        jack_disconnect "$vcv_l" system:playback_1 2>/dev/null || true
        jack_disconnect "$vcv_r" system:playback_2 2>/dev/null || true
        jack_connect "$vcv_l" "$sc_l" 2>/dev/null || true
        jack_connect "$vcv_r" "$sc_r" 2>/dev/null || true
        audio_ok=1
        if [ -n "$vcv_midi" ] && [ -n "$sc_midi" ]; then
            jack_connect "$sc_midi" "$vcv_midi" 2>/dev/null || true
            echo "connected VCV Rack JACK audio to SuperCollider inputs 3/4 and JACK MIDI to VCV"
            exit 0
        fi
        if /usr/local/bin/eap-vcv-midi-bridge 8 0.4; then
            echo "connected VCV Rack JACK audio to SuperCollider inputs 3/4 and ALSA MIDI to VCV"
            exit 0
        fi
        echo "connected VCV Rack JACK audio to SuperCollider inputs 3/4; MIDI bridge failed" >&2
        exit 1
    fi
    i=$((i + 1))
    sleep "$sleep_s"
done

if [ "$audio_ok" = "1" ]; then
    exit 1
fi

echo "VCV Rack or SuperCollider JACK ports were not found" >&2
exit 1
