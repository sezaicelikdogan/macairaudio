#!/bin/bash
# Rebuild + install the custom CS4208 4-channel driver for the CURRENTLY RUNNING
# kernel. Run this after any kernel upgrade if the speakers stop working.
# Reliable: always builds against the running kernel's own headers + source.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MB="$DIR/mbdrv"
K="$(uname -r)"
CIR="$MB/build/hda/codecs/cirrus"

echo "== rebuilding CS4208 driver for kernel $K =="
cd "$MB"
# stage the build tree for this kernel (downloads matching kernel source if needed)
bash install.cirrus.driver.sh -k "$K"
# apply the >=6.17 compat tweak, then compile
grep -q '\.remove' "$CIR/patch_cirrus_a1534_pcm.h" 2>/dev/null || sed -i 's/\.free/.remove/' "$CIR/patch_cirrus_a1534_pcm.h"
make -C "/lib/modules/$K/build" M="$CIR" modules

echo "== installing =="
sudo -A mkdir -p "/lib/modules/$K/updates"
sudo -A cp "$CIR/snd-hda-codec-cs420x.ko" "/lib/modules/$K/updates/"
sudo -A depmod -a
sudo -A modprobe -r snd_hda_codec_cs420x 2>/dev/null || true
sudo -A modprobe -r snd_hda_intel 2>/dev/null || true
sleep 1
sudo -A modprobe snd_hda_intel
echo "== verify =="
sleep 2
timeout 5 aplay -D hw:1,0 -c4 -f S16_LE -r48000 --dump-hw-params /dev/zero 2>&1 | grep -i "^CHANNELS" || true
echo "done — if CHANNELS includes 4, speakers are back. Restart the daemon: sudo systemctl restart mb81-speakers.service"
