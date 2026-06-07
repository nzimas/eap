#!/usr/bin/env bash
# Install the Subsequence generative sequencer for EAP lane timing.
set -euo pipefail

SUBSEQUENCE_URL="${EAP_SUBSEQUENCE_URL:-git+https://github.com/simonholliday/subsequence.git}"

run_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif [[ -n "${EAP_PI_PASSWORD:-}" ]] && command -v sudo >/dev/null 2>&1; then
        printf '%s\n' "$EAP_PI_PASSWORD" | sudo -S "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

if ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)'; then
    echo "eap-install-subsequence: Python 3.10+ required" >&2
    exit 1
fi

if ! python3 -m pip --version >/dev/null 2>&1; then
    echo "eap-install-subsequence: installing python3-pip"
    run_sudo apt-get update -qq
    run_sudo apt-get install -y python3-pip python3-venv git
fi

PIP=(python3 -m pip install --user)
if ! "${PIP[@]}" --help >/dev/null 2>&1; then
    PIP=(python3 -m pip install --break-system-packages)
fi

if ! "${PIP[@]}" "$SUBSEQUENCE_URL"; then
    echo "eap-install-subsequence: retrying with --break-system-packages" >&2
    python3 -m pip install --break-system-packages "$SUBSEQUENCE_URL"
fi

python3 - <<'PY'
import subsequence
print("subsequence", subsequence.__file__)
PY

echo "Subsequence installed."
