#!/bin/bash
# MacBook8,1 internal keyboard/trackpad fix installer.
# The keyboard+trackpad are SPI devices (applespi). On some cold boots the
# DesignWare LPSS DMA driver (dw_dmac) wins a module-load race and SPI uses
# DMA — which is broken on this platform — so every transfer times out and
# both input devices are dead until you power-cycle. Blacklisting dw_dmac
# forces the always-working PIO path on every boot.
# Run: bash install-keyboard-fix.sh   (asks sudo)
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo install -m 644 "$DIR/blacklist-dw-dmac.conf" /etc/modprobe.d/blacklist-dw-dmac.conf
sudo install -m 644 "$DIR/mb81-bt-nodma.conf"     /etc/modprobe.d/mb81-bt-nodma.conf
sudo update-initramfs -u

echo
echo "Done. Reboot. Healthy-boot marker in the log:"
echo "  journalctl -k | grep 'no DMA channels available, using PIO'"
