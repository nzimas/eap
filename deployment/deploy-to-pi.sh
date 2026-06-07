#!/usr/bin/env bash
# Sync Electroacoustic Playground to a Raspberry Pi and restart services.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${EAP_PI_HOST:-we@192.168.8.12}"
REMOTE_ROOT="${EAP_REMOTE_ROOT:-/opt/electroacoustic-playground}"
RESTART="${EAP_RESTART:-1}"

usage() {
    cat <<EOF
Usage: $0

Environment:
  EAP_PI_HOST       SSH target (default: we@192.168.8.241)
  EAP_REMOTE_ROOT   Install path on Pi (default: /opt/electroacoustic-playground)
  EAP_RESTART       Restart EAP services after sync (default: 1)

Example:
  EAP_PI_HOST=we@fates.local $0
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

echo "Deploying from $ROOT to ${HOST}:${REMOTE_ROOT}"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [[ -n "${EAP_PI_PASSWORD:-}" ]] && command -v sshpass >/dev/null 2>&1; then
    export SSHPASS="$EAP_PI_PASSWORD"
    RSYNC_SSH="sshpass -e ssh ${SSH_OPTS[*]}"
    SSH_CMD=(sshpass -e ssh "${SSH_OPTS[@]}")
elif [[ -n "${EAP_PI_PASSWORD:-}" ]]; then
    echo "EAP_PI_PASSWORD is set but sshpass is not installed. Install sshpass or use SSH keys." >&2
    exit 1
else
    RSYNC_SSH="ssh ${SSH_OPTS[*]}"
    SSH_CMD=(ssh "${SSH_OPTS[@]}")
fi

rsync -avz --delete -e "$RSYNC_SSH" \
    --exclude '.git/' \
    --exclude 'vendor/' \
    --exclude 'hardware/' \
    --exclude 'docs/' \
    --exclude '__pycache__/' \
    --exclude '*.pyc' \
    --exclude 'raspios_*.img' \
    --exclude '.DS_Store' \
    "$ROOT/bin" "$ROOT/control" "$ROOT/supercollider" "$ROOT/deployment" \
    "${HOST}:${REMOTE_ROOT}/"


"${SSH_CMD[@]}" "$HOST" "REMOTE_ROOT='$REMOTE_ROOT' RESTART='$RESTART' EAP_PI_PASSWORD='${EAP_PI_PASSWORD:-}' bash -s" <<'REMOTE'
set -euo pipefail

run_sudo() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif [[ -n "${EAP_PI_PASSWORD:-}" ]]; then
        printf '%s\n' "$EAP_PI_PASSWORD" | sudo -S "$@"
    else
        sudo "$@"
    fi
}

run_sudo install -d -m 0755 "$REMOTE_ROOT"
run_sudo chown -R we:we "$REMOTE_ROOT" 2>/dev/null || true
run_sudo install -d -m 0755 /usr/local/bin
run_sudo install -d -m 0755 /etc/systemd/system/eap-jack.service.d

run_sudo install -m 0755 "$REMOTE_ROOT/bin/eap" /usr/local/bin/eap

for script in "$REMOTE_ROOT/deployment/scripts/"*.py; do
    name="$(basename "$script" .py)"
    run_sudo install -m 0755 "$script" "/usr/local/bin/$name"
done
for script in "$REMOTE_ROOT/deployment/scripts/"*.sh; do
    name="$(basename "$script" .sh)"
    if [[ ! -x "/usr/local/bin/$name" ]]; then
        run_sudo install -m 0755 "$script" "/usr/local/bin/$name"
    fi
done

tmp_wrapper="$(mktemp)"
cat >"$tmp_wrapper" <<'WRAPPER'
#!/usr/bin/env bash
exec /usr/bin/python3 /opt/electroacoustic-playground/control/eap_launchpad.py "$@"
WRAPPER
run_sudo install -m 0755 "$tmp_wrapper" /usr/local/bin/eap-launchpad
rm -f "$tmp_wrapper"

for unit in eap-jack eap-subsequence eap-supercollider eap-sc-connect eap-launchpad eap-dexed eap-dexed-connect eap-vital eap-vital-connect eap-vcv eap-vcv-connect eap-console-status eap-k3-shutdown; do
    if [[ -f "$REMOTE_ROOT/deployment/systemd/${unit}.service" ]]; then
        run_sudo install -m 0644 "$REMOTE_ROOT/deployment/systemd/${unit}.service" "/etc/systemd/system/${unit}.service"
    fi
done

if [[ -f "$REMOTE_ROOT/deployment/systemd/eap-jack-override.conf" ]]; then
    run_sudo install -m 0644 "$REMOTE_ROOT/deployment/systemd/eap-jack-override.conf" \
        /etc/systemd/system/eap-jack.service.d/override.conf
fi

if [[ -d "$REMOTE_ROOT/deployment/systemd/getty@tty1.service.d" ]]; then
    run_sudo install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
    run_sudo install -m 0644 "$REMOTE_ROOT/deployment/systemd/getty@tty1.service.d/autologin.conf" \
        /etc/systemd/system/getty@tty1.service.d/autologin.conf
fi

run_sudo systemctl daemon-reload
run_sudo systemctl enable eap-jack.service eap-subsequence.service eap-supercollider.service eap-sc-connect.service eap-launchpad.service \
    eap-console-status.service eap-k3-shutdown.service 2>/dev/null || true
run_sudo systemctl disable eap-dexed.service eap-dexed-connect.service eap-vital.service eap-vital-connect.service 2>/dev/null || true
if [[ -f /etc/default/eap-vcv ]] && grep -q '^EAP_ENABLE_VCV=1' /etc/default/eap-vcv; then
    run_sudo systemctl enable eap-vcv.service eap-vcv-connect.service 2>/dev/null || true
else
    run_sudo systemctl disable eap-vcv.service eap-vcv-connect.service 2>/dev/null || true
fi

if [[ -f /etc/default/eap-vcv ]]; then
    run_sudo sed -i 's/^EAP_ENABLE_VCV=1/EAP_ENABLE_VCV=0/' /etc/default/eap-vcv 2>/dev/null || true
fi

if [[ "$RESTART" == "1" ]]; then
    run_sudo pkill -f '[R]ack .*-h ' 2>/dev/null || true
    run_sudo pkill -x eap-airwindows-host 2>/dev/null || true
    run_sudo systemctl reset-failed eap-jack.service eap-subsequence.service eap-supercollider.service 2>/dev/null || true
    run_sudo systemctl restart eap-jack.service
    sleep 2
    if [[ -x /usr/local/bin/eap-install-subsequence ]]; then
        EAP_PI_PASSWORD="${EAP_PI_PASSWORD:-}" /usr/local/bin/eap-install-subsequence || true
    fi
    run_sudo systemctl restart eap-subsequence.service
    sleep 1
    run_sudo systemctl restart eap-supercollider.service
    sleep 5
    run_sudo systemctl restart eap-sc-connect.service 2>/dev/null || true
    run_sudo systemctl stop eap-vcv-connect.service eap-vcv.service eap-dexed-connect.service eap-dexed.service 2>/dev/null || true
    run_sudo systemctl restart eap-launchpad.service
    run_sudo systemctl restart eap-console-status.service 2>/dev/null || true
fi

if [[ -x /usr/local/bin/eap-vcv-install-seeds ]]; then
    /usr/local/bin/eap-vcv-install-seeds || true
fi
if [[ -x /usr/local/bin/eap-vcv-sync-patches ]]; then
    /usr/local/bin/eap-vcv-sync-patches --reindex || true
fi

echo "Deployed to $REMOTE_ROOT"
run_sudo systemctl is-active eap-jack.service eap-subsequence.service eap-supercollider.service eap-launchpad.service || true
REMOTE

echo "Done."
