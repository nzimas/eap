#!/usr/bin/env bash
set -euo pipefail

BOOT="${BOOT:-/Volumes/bootfs}"
SSID="${SSID:-LMT-866D}"
WIFI_PASSWORD="${WIFI_PASSWORD:-}"
TARGET_HOSTNAME="${TARGET_HOSTNAME:-fates-playground}"
USERNAME="${USERNAME:-we}"
PASSWORD_HASH="${PASSWORD_HASH:-}"
COUNTRY="${COUNTRY:-LV}"

if [[ -z "$WIFI_PASSWORD" ]]; then
  echo "Set WIFI_PASSWORD before running." >&2
  exit 1
fi

if [[ -z "$PASSWORD_HASH" ]]; then
  PASSWORD_HASH="$(openssl passwd -6 'sleep')"
fi

if [[ ! -d "$BOOT" ]]; then
  echo "Boot partition not mounted at $BOOT" >&2
  exit 1
fi

if [[ ! -f "$BOOT/user-data" || ! -f "$BOOT/network-config" ]]; then
  echo "$BOOT does not look like the cloud-init boot partition." >&2
  exit 1
fi

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

write_files:
  - path: /usr/local/sbin/playground-ready
    permissions: '0755'
    owner: root:root
    content: |
      #!/bin/sh
      printf '\\n\\nSystem ready\\n' > /dev/tty1

  - path: /etc/systemd/system/playground-ready.service
    permissions: '0644'
    owner: root:root
    content: |
      [Unit]
      Description=Electroacoustic Playground boot ready message
      After=multi-user.target network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/playground-ready

      [Install]
      WantedBy=multi-user.target

runcmd:
  - [ systemctl, enable, ssh ]
  - [ systemctl, start, ssh ]
  - [ systemctl, enable, playground-ready.service ]
  - [ systemctl, start, playground-ready.service ]

final_message: "Electroacoustic Playground base system ready."
USERDATA_EOF

cat > "$BOOT/network-config" <<NETWORK_EOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: true
      optional: true
  wifis:
    wlan0:
      dhcp4: true
      optional: false
      regulatory-domain: $COUNTRY
      access-points:
        "$SSID":
          password: "$WIFI_PASSWORD"
NETWORK_EOF

rm -f "$BOOT/userconf.txt" "$BOOT/wpa_supplicant.conf" "$BOOT/firstrun.sh" "$BOOT/ssh"

cat > "$BOOT/ELECTROACOUSTIC_PLAYGROUND_BOOTFS.txt" <<MARKER_EOF
Configured for Electroacoustic Playground first boot.

Hostname: $TARGET_HOSTNAME
User: $USERNAME
Wi-Fi SSID: $SSID
Country: $COUNTRY

Provisioning format: cloud-init user-data + network-config
MARKER_EOF

sync
echo "Patched $BOOT for cloud-init first boot."
