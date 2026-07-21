#!/bin/bash
# Install + activate the already-compiled patched CS4208 driver.
# Reversible: run  finish_build.sh --uninstall  to restore the stock driver.
set -e
S=/tmp/claude-1000/-home-sezai/87a4f7fc-0a0b-49ad-a0d3-52c2d9b1056b/scratchpad/mbdrv
CIR=$S/build/hda/codecs/cirrus
KREL=$(uname -r)
UPD=/lib/modules/$KREL/updates

if [[ "$1" == "--uninstall" ]]; then
  echo "== removing custom driver, restoring stock =="
  sudo -A rm -f $UPD/snd-hda-codec-cs420x.ko
  sudo -A depmod -a
  sudo -A modprobe -r snd_hda_codec_cs420x 2>/dev/null || true
  sudo -A modprobe -r snd_hda_intel 2>/dev/null || true
  sleep 1
  sudo -A modprobe snd_hda_intel
  echo "restored stock driver. A reboot is the cleanest way to be sure."
  exit 0
fi

# (re)build only if the module is missing
if [[ ! -f $CIR/snd-hda-codec-cs420x.ko ]]; then
  echo "== compiling module =="
  make -C /lib/modules/$KREL/build M=$CIR modules
fi
ls -la $CIR/snd-hda-codec-cs420x.ko

echo "== installing to $UPD =="
sudo -A mkdir -p $UPD
sudo -A cp $CIR/snd-hda-codec-cs420x.ko $UPD/
sudo -A depmod -a
echo "module now resolves to: $(modinfo -n snd_hda_codec_cs420x 2>/dev/null)"

echo "== reloading HDA stack (audio drops briefly) =="
systemctl --user stop pipewire pipewire-pulse wireplumber 2>/dev/null || true
sudo -A modprobe -r snd_hda_codec_cs420x 2>/dev/null || true
sudo -A modprobe -r snd_hda_intel 2>/dev/null || true
sleep 1
sudo -A modprobe snd_hda_intel
sleep 3
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true

echo "== verify =="
echo "loaded cs420x from: $(modinfo -n snd_hda_codec_cs420x 2>/dev/null)"
lsmod | grep -E "snd_hda_codec_cs420x" || echo "(cs420x module not shown in lsmod yet)"
aplay -l 2>/dev/null | grep -i CS4208 || echo "(CS4208 card not listed)"
echo "--- recent codec dmesg ---"
sudo -A dmesg | grep -iE "cs4208|cs420x|a1534|cirrus|snd_hda_codec" | tail -15
echo
echo "== DONE. Test speakers now, e.g.:  speaker-test -Dhw:1,0 -c2 -twav -l1"
echo "   (or just play any audio). If headphones broke, run: bash $0 --uninstall"
