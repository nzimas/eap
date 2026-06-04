#!/bin/sh
# Restart the full EAP audio stack in dependency order.
set -eu

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

systemctl stop eap-launchpad.service eap-console-status.service 2>/dev/null || true
systemctl stop eap-vcv-connect.service eap-vital-connect.service eap-dexed-connect.service eap-sc-connect.service 2>/dev/null || true
systemctl stop eap-vcv.service eap-vital.service eap-dexed.service eap-supercollider.service 2>/dev/null || true
/usr/local/bin/eap-airwindows-grid-fx --stop 2>/dev/null || true
pkill -x eap-airwindows-host 2>/dev/null || true
pkill -x jalv 2>/dev/null || true
pkill -f '[v]italium' 2>/dev/null || true
pkill -f '[e]ap-start-vital' 2>/dev/null || true
pkill -f '[e]ap-start-vcv' 2>/dev/null || true
pkill -f '[R]ack.*-h' 2>/dev/null || true
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
