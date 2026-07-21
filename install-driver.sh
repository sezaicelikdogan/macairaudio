#!/bin/bash
# Install the already-compiled custom CS4208 driver (4-channel PCM) for the
# RUNNING kernel, and reload the HDA stack. Location-independent.
# This restores the 4ch hw:1,0 PCM the speakers need. (For kernel-upgrade-proofing,
# run install-dkms.sh afterwards.)
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CIR="$DIR/mbdrv/build/hda/codecs/cirrus"
K="$(uname -r)"
KO="$CIR/snd-hda-codec-cs420x.ko"

if [[ ! -f "$KO" ]]; then
  echo "ERROR: compiled module not found at $KO"
  echo "Rebuild with: cd $DIR/mbdrv && bash install.cirrus.driver.sh -k $K && make -C /lib/modules/$K/build M=$CIR modules"
  exit 1
fi

# sanity: module must match the running kernel
MV=$(modinfo "$KO" 2>/dev/null | awk '/^vermagic/{print $2}')
echo "module vermagic: $MV  (running kernel: $K)"
[[ "$MV" != "$K" ]] && { echo "ERROR: vermagic mismatch — module is for $MV, not $K"; exit 1; }

echo "== installing to /lib/modules/$K/updates/ =="
sudo -A mkdir -p "/lib/modules/$K/updates"
sudo -A cp "$KO" "/lib/modules/$K/updates/snd-hda-codec-cs420x.ko"
sudo -A depmod -a
echo "resolves to: $(modinfo -n snd_hda_codec_cs420x 2>/dev/null)"

echo "== reloading HDA stack (audio drops briefly) =="
systemctl --user stop pipewire pipewire-pulse wireplumber 2>/dev/null || true
sudo -A modprobe -r snd_hda_codec_cs420x 2>/dev/null || true
sudo -A modprobe -r snd_hda_intel 2>/dev/null || true
sleep 1
sudo -A modprobe snd_hda_intel
sleep 3
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo "== verify 4-channel PCM is back =="
sleep 1
timeout 5 aplay -D hw:1,0 -c4 -f S16_LE -r48000 --dump-hw-params /dev/zero 2>&1 | grep -i "^CHANNELS" || true
echo "loaded driver: $(modinfo -n snd_hda_codec_cs420x 2>/dev/null)"
echo "== DONE. If CHANNELS shows 4 (or a range up to 4+), the driver is good. =="
