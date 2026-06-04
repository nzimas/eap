#!/bin/sh
set -eu

tty="${1:-/dev/tty1}"
interval_s="${2:-2}"

if [ ! -w "$tty" ]; then
    exit 0
fi

health_status() {
    if systemctl is-active --quiet eap-jack.service \
        && systemctl is-active --quiet eap-supercollider.service \
        && systemctl is-active --quiet eap-launchpad.service; then
        printf "OK"
    elif systemctl is-failed --quiet eap-jack.service \
        || systemctl is-failed --quiet eap-supercollider.service \
        || systemctl is-failed --quiet eap-launchpad.service; then
        printf "FAIL"
    else
        printf "BOOT"
    fi
}

cpu_level() {
    awk '
        NR == 1 {
            cores = 0
            while (getline line < "/proc/cpuinfo") {
                if (line ~ /^processor[[:space:]]*:/) cores++
            }
            close("/proc/cpuinfo")
            if (cores < 1) cores = 1
            level = int(($1 / cores) * 100)
            if (level > 999) level = 999
            printf "%d%%", level
        }
    ' /proc/loadavg
}

ram_level() {
    awk '
        /^MemTotal:/ { total = $2 }
        /^MemAvailable:/ { available = $2 }
        END {
            if (total <= 0) {
                printf "?%%"
            } else {
                printf "%d%%", int(((total - available) / total) * 100)
            }
        }
    ' /proc/meminfo
}

launchpad_status() {
    if systemctl is-active --quiet eap-launchpad.service \
        && amidi -l 2>/dev/null | grep -q "Launchpad Mini MK3"; then
        printf "ONLINE"
    elif amidi -l 2>/dev/null | grep -q "Launchpad Mini MK3"; then
        printf "WAIT"
    else
        printf "MISSING"
    fi
}

printf '\033[2J\033[?25l\033[H' > "$tty"

while true; do
    line_1="EAP - $(health_status)"
    line_2="CPU $(cpu_level) + RAM $(ram_level)"
    line_3="LP - $(launchpad_status)"

    {
        printf '\033[H'
        printf '%-32.32s\n' "$line_1"
        printf '%-32.32s\n' "$line_2"
        printf '%-32.32s\n' "$line_3"
    } > "$tty"
    sleep "$interval_s"
done
