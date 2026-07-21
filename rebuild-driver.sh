#!/bin/bash
# Manual fallback: rebuild + install the custom CS4208 4-channel driver for the
# CURRENTLY RUNNING kernel, outside DKMS. Normally NOT needed — install-driver.sh
# registers the driver with DKMS which rebuilds automatically on kernel upgrades.
# Use this only if the DKMS path fails. Downloads matching kernel source from
# kernel.org on first use (~150 MB).
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MB="$DIR/mbdrv"
K="$(uname -r)"
CIR="$MB/build/hda/codecs/cirrus"

echo "== rebuilding CS4208 driver for kernel $K =="
cd "$MB"
# stage the build tree for this kernel (downloads matching kernel source if needed)
bash install.cirrus.driver.sh -k "$K"
make -C "/lib/modules/$K/build" M="$CIR" modules

echo "== installing =="
sudo mkdir -p "/lib/modules/$K/updates"
sudo cp "$CIR/snd-hda-codec-cs420x.ko" "/lib/modules/$K/updates/"
sudo depmod -a
sudo modprobe -r snd_hda_codec_cs420x 2>/dev/null || true
sudo modprobe -r snd_hda_intel 2>/dev/null || true
sleep 1
sudo modprobe snd_hda_intel
echo "== verify =="
sleep 2
timeout 5 aplay -D hw:CARD=PCH,DEV=0 -c4 -f S16_LE -r48000 --dump-hw-params /dev/zero 2>&1 | grep -i "^CHANNELS" || true
echo "done — if CHANNELS includes 4, speakers are back. Restart the daemon: sudo systemctl restart mb81-speakers.service"
