#!/bin/bash
# PROVEN working MacBook8,1 internal-speaker enable (verified audible 2026-07-21).
# Plays a moderate test tone through the internal speakers.
# Requires: custom snd-hda-codec-cs420x.ko installed (see mbdrv/), sudo -A askpass.
HW=/dev/snd/hwC1D0
DIR="$(cd "$(dirname "$0")" && pwd)"
v() { sudo -A hda-verb $HW "$1" "$2" "$3" >/dev/null 2>&1; }
rd() { sudo -A hda-verb $HW "$1" "$2" 0 2>/dev/null | grep -oE '0x[0-9a-f]+$' | tail -1; }
coef() { v 0x24 0x500 0x$1; v 0x24 0x400 0x$2; }

# generate a comfortable 4-channel test tone (300Hz, amp 0.22) if missing
TONE=/tmp/mb81_tone.wav
python3 - "$TONE" <<'EOF'
import math,struct,wave,sys
w=wave.open(sys.argv[1],"w"); w.setnchannels(4); w.setsampwidth(2); w.setframerate(44100)
fr=bytearray(); N=44100*12
for i in range(N):
    fade=min(1.0,i/11025,(N-i)/11025); a=0.22*fade
    s=int(a*32767*math.sin(2*math.pi*300*i/44100)); fr+=struct.pack("<hhhh",s,s,s,s)
w.writeframes(bytes(fr)); w.close()
EOF

systemctl --user stop pipewire pipewire-pulse wireplumber pipewire.socket pipewire-pulse.socket 2>/dev/null
sleep 1
echo 0 | sudo -A tee /sys/module/snd_hda_intel/parameters/power_save >/dev/null
amixer -c 1 sset Master 60% unmute >/dev/null 2>&1

nohup aplay -D hw:1,0 --buffer-size=16384 "$TONE" >/tmp/mb81_ap.log 2>&1 &
sleep 2
tag=$(( $(rd 0x02 0xf06) >> 4 ))

# ---- the proven recipe (4-channel digital speaker path) ----
v 0x0a 0x705 0x00                       # converter D0
v 0x0a 0x200 0x4013                     # 4-channel format (THE key)
v 0x0a 0x72d 0x03                       # channel count = 4
v 0x0a 0x706 $(( tag<<4 ))              # bind live stream tag
v 0x24 0x703 0x01                       # vendor proc on
coef 00 00c4; coef 04 0c04; coef 05 1000; coef 03 0baa
coef 02 003a; coef 36 0034; coef 19 8383; coef 1c 0010
v 0x0a 0x70d 0x01; v 0x0a 0x70e 0x01; v 0x0a 0x70d 0x11   # DigEn
v 0x1d 0x701 0x00; v 0x1d 0x707 0x40; v 0x1d 0x705 0x00   # speaker pin OUT
v 0x01 0x716 0x09; v 0x01 0x717 0x01; v 0x01 0x715 0x01   # GPIO0 amp ON

echo "state: DIGI1=$(rd 0x0a 0xf0d) conv=$(rd 0x0a 0xf06) GPIO=$(rd 0x01 0xf15)"
echo ">>> playing ~10s of 300Hz through internal speakers <<<"
sleep 10
pkill aplay 2>/dev/null
systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null
echo done
