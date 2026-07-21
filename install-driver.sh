#!/bin/bash
# Build + install the custom CS4208 driver (4-channel digital speaker PCM) from
# source and register it with DKMS, so it auto-rebuilds on every kernel upgrade.
# Works from a fresh clone. First build downloads the matching kernel source
# from kernel.org (~150 MB, needs network) — later kernel upgrades reuse it.
# Uninstall: bash install-driver.sh --uninstall
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME=macbook12-audio-driver
VER=0.1
SRC=/usr/src/$NAME-$VER
K="$(uname -r)"

if [[ "$1" == "--uninstall" ]]; then
  sudo dkms remove "$NAME/$VER" --all 2>/dev/null || true
  sudo rm -rf "$SRC"
  echo "removed DKMS module + $SRC (reboot or 'sudo modprobe -r snd_hda_intel; sudo modprobe snd_hda_intel' to drop it)"
  exit 0
fi

echo "== 0/4 checking build dependencies =="
missing=()
for c in dkms gcc make; do command -v "$c" >/dev/null || missing+=("$c"); done
[[ -d "/lib/modules/$K/build" ]] || missing+=("linux-headers-$K")
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Missing: ${missing[*]}"
  echo "Install with: sudo apt install dkms build-essential linux-headers-\$(uname -r)"
  exit 1
fi

echo "== 1/4 staging driver source to $SRC =="
sudo rm -rf "$SRC"
sudo mkdir -p "$SRC"
tar -C "$DIR/mbdrv" --exclude=build -cf - . | sudo tar -C "$SRC" -xf -

echo "== 2/4 DKMS build + install (kernel $K; first run downloads kernel source) =="
sudo dkms remove "$NAME/$VER" --all 2>/dev/null || true
sudo dkms install "$NAME/$VER" --force

echo "== 3/4 reloading HDA stack (audio drops briefly) =="
systemctl --user stop pipewire pipewire-pulse wireplumber 2>/dev/null || true
sudo modprobe -r snd_hda_codec_cs420x 2>/dev/null || true
sudo modprobe -r snd_hda_intel 2>/dev/null || true
sleep 1
sudo modprobe snd_hda_intel
sleep 3
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo "== 4/4 verify =="
sleep 1
echo "loaded driver: $(modinfo -n snd_hda_codec_cs420x 2>/dev/null)"
echo "  (should be under /lib/modules/$K/updates/dkms/)"
timeout 5 aplay -D hw:CARD=PCH,DEV=0 -c4 -f S16_LE -r48000 --dump-hw-params /dev/zero 2>&1 | grep -i "^CHANNELS" || true
echo "== DONE. If CHANNELS shows 4 (or a range up to 4+), the driver is good. =="
echo "DKMS rebuilds it automatically on kernel upgrades (AUTOINSTALL=yes)."
