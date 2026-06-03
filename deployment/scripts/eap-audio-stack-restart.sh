#!/bin/sh
# Restart the full EAP audio stack in dependency order.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

systemctl stop eap-launchpad.service eap-console-status.service 2>/dev/null || true
systemctl stop eap-dexed-connect.service eap-sc-connect.service 2>/dev/null || true
systemctl stop eap-dexed.service eap-supercollider.service 2>/dev/null || true
systemctl stop eap-jack.service 2>/dev/null || true

sleep 1
systemctl start eap-jack.service
sleep 2
/usr/local/bin/eap-alsa-mixer 2>/dev/null || true
systemctl start eap-supercollider.service
sleep 8
systemctl start eap-sc-connect.service
systemctl start eap-launchpad.service
systemctl start eap-console-status.service 2>/dev/null || true

systemctl is-active eap-jack.service eap-supercollider.service eap-sc-connect.service eap-launchpad.service
