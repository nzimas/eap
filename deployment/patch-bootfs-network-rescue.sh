#!/usr/bin/env bash
set -euo pipefail

BOOT="${BOOT:-/Volumes/bootfs}"
SSID="${SSID:-LMT-866D}"
WIFI_PASSWORD="${WIFI_PASSWORD:-}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-fates-playground}"
USERNAME="${USERNAME:-we}"
USER_PASSWORD="${USER_PASSWORD:-sleep}"
COUNTRY="${COUNTRY:-LV}"

if [[ -z "$WIFI_PASSWORD" ]]; then
  echo "Set WIFI_PASSWORD before running." >&2
  exit 1
fi

if [[ ! -d "$BOOT" ]]; then
  echo "Boot partition not mounted at $BOOT" >&2
  exit 1
fi

PASSWORD_HASH="$(openssl passwd -6 "$USER_PASSWORD")"

touch "$BOOT/ssh"
printf '%s:%s\n' "$USERNAME" "$PASSWORD_HASH" > "$BOOT/userconf.txt"

cat > "$BOOT/custom.toml" <<CUSTOM_EOF
config_version = 1

[system]
hostname = "$TARGET_HOSTNAME"

[user]
name = "$USERNAME"
password = "$PASSWORD_HASH"
password_encrypted = true

[ssh]
enabled = true
password_authentication = true

[wlan]
ssid = "$SSID"
password = "$WIFI_PASSWORD"
password_encrypted = false
hidden = false
country = "$COUNTRY"

[locale]
timezone = "Europe/Riga"
keymap = "us"
CUSTOM_EOF

if [[ -f "$BOOT/user-data" ]]; then
  cat > "$BOOT/user-data" <<USERDATA_EOF
#cloud-config
hostname: $TARGET_HOSTNAME
manage_etc_hosts: true
ssh_pwauth: true
disable_root: true

users:
  - name: $USERNAME
    gecos: Electroacoustic Playground
    groups: adm,audio,dialout,plugdev,sudo,users,video,netdev
    shell: /bin/bash
    lock_passwd: false
    passwd: '$PASSWORD_HASH'
    sudo: ALL=(ALL) NOPASSWD:ALL

runcmd:
  - [ systemctl, enable, ssh ]
  - [ systemctl, start, ssh ]

final_message: "Electroacoustic Playground network rescue ready."
USERDATA_EOF
fi

if [[ -f "$BOOT/network-config" ]]; then
  cat > "$BOOT/network-config" <<NETWORK_EOF
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    eth0:
      dhcp4: true
      optional: true
  wifis:
    wlan0:
      dhcp4: true
      optional: true
      regulatory-domain: $COUNTRY
      access-points:
        "$SSID":
          password: "$WIFI_PASSWORD"
NETWORK_EOF
fi

if [[ -f "$BOOT/meta-data" ]]; then
  perl -0pi -e "s/instance_id: .*/instance_id: electroacoustic-network-rescue-$(date +%Y%m%d%H%M%S)/" "$BOOT/meta-data"
fi

CONFIG="$BOOT/config.txt"
if [[ -f "$CONFIG" ]]; then
  perl -0pi -e 's/^dtparam=i2c_arm=on/# rescue-disabled: dtparam=i2c_arm=on/mg;
                s/^dtparam=spi=on/# rescue-disabled: dtparam=spi=on/mg;
                s/^dtparam=i2s=on/# rescue-disabled: dtparam=i2s=on/mg;
                s/^dtoverlay=i2s-mmap/# rescue-disabled: dtoverlay=i2s-mmap/mg;
                s/^enable_uart=1/# rescue-disabled: enable_uart=1/mg;
                s/^dtoverlay=rpi-proto/# rescue-disabled: dtoverlay=rpi-proto/mg;
                s/^dtoverlay=fates-ssd1322,rotate=180/# rescue-disabled: dtoverlay=fates-ssd1322,rotate=180/mg;
                s/^dtparam=audio=off/# rescue-disabled: dtparam=audio=off/mg;' "$CONFIG"
fi

cat > "$BOOT/ELECTROACOUSTIC_PLAYGROUND_RESCUE.txt" <<MARKER_EOF
Network rescue boot configured.

Hostname: $TARGET_HOSTNAME
User: $USERNAME
Wi-Fi SSID: $SSID
Country: $COUNTRY

Fates overlays have been temporarily disabled in config.txt.
After SSH works, re-enable hardware overlays deliberately.
MARKER_EOF

sync
echo "Patched $BOOT for network rescue boot."
