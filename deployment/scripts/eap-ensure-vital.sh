#!/usr/bin/env bash
set -euo pipefail

tries="${1:-18}"
sleep_s="${2:-0.25}"
state_dir="${EAP_VITAL_STATE_DIR:-/home/we/.local/share/eap-vital}"
controls_file="$state_dir/current.controls"

mkdir -p "$state_dir"
touch "$controls_file"

have_ports() {
    jack_lsp 2>/dev/null | awk '
        BEGIN { left=0; right=0 }
        { line=tolower($0) }
        line ~ /vital.*:.*audio.*out.*1$/ { left=1 }
        line ~ /vital.*:.*audio.*out.*2$/ { right=1 }
        END { exit !(left && right) }
    '
}

route_ready() {
    jack_lsp -c 2>/dev/null | awk '
        BEGIN { port=""; left=0; right=0; midi=0 }
        /^[^[:space:]]/ { port=$0; next }
        port ~ /[Vv]ital.*:.*audio.*out.*1$/ && $0 ~ /SuperCollider:in_5$/ { left=1 }
        port ~ /[Vv]ital.*:.*audio.*out.*2$/ && $0 ~ /SuperCollider:in_6$/ { right=1 }
        port ~ /[Vv]ital.*:.*events.*in$/ && $0 ~ /SuperCollider.*out0/ { midi=1 }
        END { exit !(left && right && midi) }
    '
}

if ! command -v jalv >/dev/null 2>&1; then
    echo "vital requested; jalv missing"
    exit 0
fi
if ! lv2ls 2>/dev/null | grep -qx "${EAP_VITAL_LV2_URI:-urn:distrho:vitalium}"; then
    echo "vital requested; Vitalium LV2 missing"
    exit 0
fi

if ! have_ports; then
    EAP_ENABLE_VITAL=1 /usr/local/bin/eap-start-vital "$controls_file" >/dev/null 2>&1 || true
fi

i=0
while [ "$i" -lt "$tries" ]; do
    if have_ports; then
        if ! route_ready; then
            EAP_ENABLE_VITAL=1 /usr/local/bin/eap-connect-vital-jack 12 0.15 >/dev/null 2>&1 || true
        fi
        echo "vital ready"
        exit 0
    fi
    i=$((i + 1))
    sleep "$sleep_s"
done

EAP_ENABLE_VITAL=1 /usr/local/bin/eap-connect-vital-jack 1 0.1 >/dev/null 2>&1 || true
echo "vital requested; ports not visible yet"
exit 0
