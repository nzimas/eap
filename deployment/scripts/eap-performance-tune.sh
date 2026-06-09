#!/usr/bin/env bash
set -euo pipefail

for governor in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [[ -w "$governor" ]]; then
        printf 'performance' >"$governor"
    fi
done
