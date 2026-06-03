#!/bin/sh
# WM8731 output path for Fates / snd_rpi_proto
set -eu

card="${EAP_ALSA_CARD:-sndrpiproto}"

if ! amixer -c "$card" sget Master >/dev/null 2>&1; then
    echo "EAP mixer: card $card not found" >&2
    exit 1
fi

amixer -c "$card" sset Master 115 115 unmute 2>/dev/null || amixer -c "$card" sset Master 115 115 2>/dev/null || true
amixer -c "$card" sset "Output Mixer HiFi Playback" on 2>/dev/null || true
amixer -c "$card" sset "Output Mixer Line Bypass" off 2>/dev/null || true
amixer -c "$card" sset "Output Mixer Mic Sidetone" off 2>/dev/null || true
echo "EAP mixer: Master and HiFi playback enabled on $card"
