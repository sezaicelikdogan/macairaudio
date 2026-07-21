#!/bin/bash
# Install the MacBook8,1 internal-speaker permanent fix (root parts):
# codec daemon + its MMIO stream-tag reader, systemd service, power_save=0,
# suspend/resume hook. User-side PipeWire setup: run mb81-setup.sh afterwards.
# Uninstall: bash install-service.sh --uninstall
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$1" == "--uninstall" ]]; then
  echo "== removing speaker service =="
  sudo systemctl disable --now mb81-speakers.service 2>/dev/null || true
  sudo rm -f /usr/local/sbin/mb81-speaker-assert.sh \
             /usr/local/sbin/mb81-dmatag.py \
             /etc/systemd/system/mb81-speakers.service \
             /etc/modprobe.d/mb81-speaker.conf \
             /usr/lib/systemd/system-sleep/mb81-speaker
  sudo systemctl daemon-reload
  echo "removed. (driver: bash install-driver.sh --uninstall)"
  exit 0
fi

echo "== 1/6 install assert daemon =="
sudo install -m755 "$DIR/mb81-speaker-assert.sh" /usr/local/sbin/mb81-speaker-assert.sh

echo "== 2/6 install DMA stream-tag reader (daemon dependency) =="
sudo install -m755 "$DIR/mb81-dmatag.py" /usr/local/sbin/mb81-dmatag.py

echo "== 3/6 install systemd service =="
sudo install -m644 "$DIR/mb81-speakers.service" /etc/systemd/system/mb81-speakers.service

echo "== 4/6 install power_save=0 module option =="
sudo install -m644 "$DIR/mb81-speaker.modprobe.conf" /etc/modprobe.d/mb81-speaker.conf
echo 0 | sudo tee /sys/module/snd_hda_intel/parameters/power_save >/dev/null 2>&1 || true

echo "== 5/6 install resume hook =="
sudo install -m755 "$DIR/mb81-speaker-resume" /usr/lib/systemd/system-sleep/mb81-speaker

echo "== 6/6 enable + start service =="
sudo systemctl daemon-reload
sudo systemctl enable --now mb81-speakers.service

echo
echo "== status =="
sudo systemctl --no-pager status mb81-speakers.service | head -6
echo
echo "DONE. Next: bash mb81-setup.sh   (PipeWire sink + login services)"
echo "Then play any audio (YouTube, music) with headphones UNPLUGGED."
echo 'Verify: grep channels /proc/asound/PCH/pcm0p/sub0/hw_params   (should be 4 while playing)'
