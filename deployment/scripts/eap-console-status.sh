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
        && systemctl is-active --quiet eap-dexed.service \
        && systemctl is-active --quiet eap-launchpad.service; then
        printf "OK"
    elif systemctl is-failed --quiet eap-jack.service \
        || systemctl is-failed --quiet eap-supercollider.service \
        || systemctl is-failed --quiet eap-dexed.service \
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

line_at() {
    row="$1"
    text="$2"
    printf '\033[%s;1H%-32.32s' "$row" "$text"
}

previous_line_1=""
previous_line_2=""
previous_line_3=""

printf '\033[2J\033[?25l\033[H' > "$tty"

while true; do
    line_1="EAP - $(health_status)"
    line_2="CPU $(cpu_level) + RAM $(ram_level)"
    line_3="LP - $(launchpad_status)"

    if [ "$line_1" != "$previous_line_1" ]; then
        line_at 1 "$line_1" > "$tty"
        previous_line_1="$line_1"
    fi
    if [ "$line_2" != "$previous_line_2" ]; then
        line_at 2 "$line_2" > "$tty"
        previous_line_2="$line_2"
    fi
    if [ "$line_3" != "$previous_line_3" ]; then
        line_at 3 "$line_3" > "$tty"
        previous_line_3="$line_3"
    fi
    sleep "$interval_s"
done
