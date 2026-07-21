#!/bin/bash
# MacBook8,1 Bluetooth fix installer (BCM4350C0 UART).
# Installs: (1) a boot service that heals the adapter's cold-init failure with a
# fast serdev rebind, and (2) a per-user session daemon that keeps a connect armed
# for paired BLE devices (this chip's firmware corrupts some advertising reports,
# which makes BlueZ's native auto-reconnect unreliable) and re-syncs the GNOME
# Quick Settings Bluetooth toggle after the late adapter init.
# Run as your normal user: bash install-bluetooth.sh   (asks sudo when needed)
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== system part (sudo): boot-time adapter heal =="
sudo install -m 755 "$DIR/fix-macbook-bluetooth.sh" /usr/local/sbin/fix-macbook-bluetooth.sh
sudo install -m 644 "$DIR/fix-macbook-bluetooth.service" /etc/systemd/system/fix-macbook-bluetooth.service
sudo systemctl daemon-reload
sudo systemctl enable fix-macbook-bluetooth.service

echo "== user part: session daemon (auto-connect + tray toggle) =="
install -D -m 755 "$DIR/mb81-bt-postboot.sh" "$HOME/.local/bin/mb81-bt-postboot.sh"
install -D -m 644 "$DIR/mb81-bt-postboot.service" "$HOME/.config/systemd/user/mb81-bt-postboot.service"
systemctl --user daemon-reload
systemctl --user enable --now mb81-bt-postboot.service

echo
echo "Done. Pair your devices once with bluetoothctl or GNOME Settings;"
echo "after that they reconnect automatically whenever they are moved/woken."
echo "Daemon log: journalctl --user -t mb81-bt-postboot.sh  (or grep 'mb81-bt]')"
