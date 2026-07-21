#!/bin/bash
# Install the MacBook8,1 internal-speaker permanent fix (root parts).
# The user-side profile service is already installed separately.
# Uninstall: bash install-service.sh --uninstall
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$1" == "--uninstall" ]]; then
  echo "== removing speaker service =="
  sudo -A systemctl disable --now mb81-speakers.service 2>/dev/null || true
  sudo -A rm -f /usr/local/sbin/mb81-speaker-assert.sh \
                /etc/systemd/system/mb81-speakers.service \
                /etc/modprobe.d/mb81-speaker.conf \
                /usr/lib/systemd/system-sleep/mb81-speaker
  sudo -A systemctl daemon-reload
  systemctl --user disable --now mb81-set-profile.service 2>/dev/null || true
  echo "removed. (custom codec driver in /lib/modules/.../updates left in place;"
  echo " use mbdrv/finish_build.sh --uninstall to remove that too.)"
  exit 0
fi

echo "== 1/5 install assert daemon =="
sudo -A install -m755 "$DIR/mb81-speaker-assert.sh" /usr/local/sbin/mb81-speaker-assert.sh

echo "== 2/5 install systemd service =="
sudo -A install -m644 "$DIR/mb81-speakers.service" /etc/systemd/system/mb81-speakers.service

echo "== 3/5 install power_save=0 module option =="
sudo -A install -m644 "$DIR/mb81-speaker.modprobe.conf" /etc/modprobe.d/mb81-speaker.conf
echo 0 | sudo -A tee /sys/module/snd_hda_intel/parameters/power_save >/dev/null 2>&1 || true

echo "== 4/5 install resume hook =="
sudo -A install -m755 "$DIR/mb81-speaker-resume" /usr/lib/systemd/system-sleep/mb81-speaker

echo "== 5/5 enable + start service =="
sudo -A systemctl daemon-reload
sudo -A systemctl enable --now mb81-speakers.service

echo
echo "== status =="
sudo -A systemctl --no-pager status mb81-speakers.service | head -6
echo
echo "DONE. Test: play any audio (YouTube, music) with headphones UNPLUGGED."
echo "Verify:  cat /proc/asound/card1/pcm0p/sub0/hw_params | grep channels   (should be 4)"
echo "         sudo hda-verb /dev/snd/hwC1D0 0x0a 0xf0d 0                     (should be 0x111)"
