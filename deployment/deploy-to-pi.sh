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
    --exclude 'raspios_*.img' \
    --exclude '.DS_Store' \
    "$ROOT/bin" "$ROOT/control" "$ROOT/supercollider" "$ROOT/deployment" \
    "${HOST}:${REMOTE_ROOT}/"

"${SSH_CMD[@]}" "$HOST" "REMOTE_ROOT='$REMOTE_ROOT' RESTART='$RESTART' bash -s" <<'REMOTE'
set -euo pipefail

SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    SUDO="sudo"
fi

$SUDO install -d -m 0755 "$REMOTE_ROOT"
$SUDO chown -R we:we "$REMOTE_ROOT" 2>/dev/null || true
$SUDO install -d -m 0755 /usr/local/bin
$SUDO install -d -m 0755 /etc/systemd/system/eap-jack.service.d

$SUDO install -m 0755 "$REMOTE_ROOT/bin/eap" /usr/local/bin/eap

for script in "$REMOTE_ROOT/deployment/scripts/"*.sh; do
    name="$(basename "$script" .sh)"
    $SUDO install -m 0755 "$script" "/usr/local/bin/$name"
done
for script in "$REMOTE_ROOT/deployment/scripts/"*.py; do
    name="$(basename "$script" .py)"
    $SUDO install -m 0755 "$script" "/usr/local/bin/$name"
done

$SUDO tee /usr/local/bin/eap-launchpad >/dev/null <<'WRAPPER'
#!/usr/bin/env bash
exec /usr/bin/python3 /opt/electroacoustic-playground/control/eap_launchpad.py "$@"
WRAPPER
$SUDO chmod 0755 /usr/local/bin/eap-launchpad

for unit in eap-jack eap-supercollider eap-sc-connect eap-launchpad eap-dexed eap-dexed-connect eap-vital eap-vital-connect eap-console-status eap-k3-shutdown; do
    if [[ -f "$REMOTE_ROOT/deployment/systemd/${unit}.service" ]]; then
        $SUDO install -m 0644 "$REMOTE_ROOT/deployment/systemd/${unit}.service" "/etc/systemd/system/${unit}.service"
    fi
done

if [[ -f "$REMOTE_ROOT/deployment/systemd/eap-jack-p256-override.conf" ]]; then
    $SUDO install -m 0644 "$REMOTE_ROOT/deployment/systemd/eap-jack-p256-override.conf" \
        /etc/systemd/system/eap-jack.service.d/override.conf
fi

if [[ -d "$REMOTE_ROOT/deployment/systemd/getty@tty1.service.d" ]]; then
    $SUDO install -d -m 0755 /etc/systemd/system/getty@tty1.service.d
    $SUDO install -m 0644 "$REMOTE_ROOT/deployment/systemd/getty@tty1.service.d/autologin.conf" \
        /etc/systemd/system/getty@tty1.service.d/autologin.conf
fi

$SUDO systemctl daemon-reload
$SUDO systemctl enable eap-jack.service eap-supercollider.service eap-sc-connect.service eap-launchpad.service \
    eap-dexed.service eap-dexed-connect.service eap-console-status.service eap-k3-shutdown.service 2>/dev/null || true

if [[ "$RESTART" == "1" ]]; then
    $SUDO systemctl reset-failed eap-jack.service eap-supercollider.service 2>/dev/null || true
    $SUDO systemctl restart eap-jack.service
    sleep 2
    $SUDO systemctl restart eap-supercollider.service
    sleep 5
    $SUDO systemctl restart eap-sc-connect.service 2>/dev/null || true
    $SUDO systemctl stop eap-dexed-connect.service eap-dexed.service 2>/dev/null || true
    $SUDO systemctl restart eap-launchpad.service
    $SUDO systemctl restart eap-console-status.service 2>/dev/null || true
fi

echo "Deployed to $REMOTE_ROOT"
$SUDO systemctl is-active eap-jack.service eap-supercollider.service eap-launchpad.service || true
REMOTE

echo "Done."
