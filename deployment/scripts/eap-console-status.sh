#!/bin/sh
set -eu

tty="${1:-/dev/tty1}"

if [ ! -w "$tty" ]; then
    exit 0
fi

service_state() {
    if systemctl is-active --quiet "$1"; then
        printf "ok"
    else
        printf "wait"
    fi
}

{
    printf '\033c'
    printf 'Electroacoustic Playground\n'
    printf '==========================\n\n'
    printf 'JACK:           %s\n' "$(service_state eap-jack.service)"
    printf 'SuperCollider:  %s\n' "$(service_state eap-supercollider.service)"
    printf 'Dexed:          %s\n' "$(service_state eap-dexed.service)"
    printf 'Launchpad:      %s\n' "$(service_state eap-launchpad.service)"
    printf '\nSystem ready\n'
} > "$tty"
