#!/usr/bin/env bash
# Run sclang and fail the service if scsynth disappears from JACK.
set -euo pipefail

BOOT_FILE="${EAP_SC_BOOT:-/opt/electroacoustic-playground/supercollider/boot.scd}"
MISSING_LIMIT="${EAP_SC_MISSING_LIMIT:-3}"
CHECK_INTERVAL="${EAP_SC_CHECK_INTERVAL:-5}"
BOOT_GRACE="${EAP_SC_BOOT_GRACE:-25}"

/usr/bin/sclang -D "$BOOT_FILE" &
sclang_pid=$!

cleanup() {
    if kill -0 "$sclang_pid" 2>/dev/null; then
        kill "$sclang_pid" 2>/dev/null || true
        wait "$sclang_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

sleep "$BOOT_GRACE"
missing=0
while kill -0 "$sclang_pid" 2>/dev/null; do
    if jack_lsp 2>/dev/null | grep -q '^SuperCollider:out_1$'; then
        missing=0
    else
        missing=$((missing + 1))
        echo "EAP SuperCollider watchdog: missing JACK output ports (${missing}/${MISSING_LIMIT})" >&2
        if [ "$missing" -ge "$MISSING_LIMIT" ]; then
            echo "EAP SuperCollider watchdog: scsynth appears gone; restarting service" >&2
            exit 1
        fi
    fi
    sleep "$CHECK_INTERVAL"
done

wait "$sclang_pid"
