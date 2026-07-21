#!/bin/bash
# MacBook8,1 internal-speaker auto-enable daemon (runs as root via systemd).
# THE KEY on kernel 7.0: the HDA controller assigns the playback DMA a stream TAG
# dynamically, but the codec's digital speaker converter 0x0a must be bound to THAT
# exact tag or it receives silence. We read the real running tag+format from the
# controller MMIO (mb81-dmatag.py) and bind 0x0a to it. Card is resolved by stable
# id (PCH) since ALSA card numbers swap with HDMI across boots. Idempotent.
DMATAG=/usr/local/sbin/mb81-dmatag.py
v()  { hda-verb "$HW" "$1" "$2" "$3" >/dev/null 2>&1; }
rd() { hda-verb "$HW" "$1" "$2" 0 2>/dev/null | grep -oE '0x[0-9a-f]+$' | tail -1; }
coef() { v 0x24 0x500 0x$1; v 0x24 0x400 0x$2; }

resolve_card() {
  local n
  for f in /proc/asound/card*/id; do
    if [ "$(cat "$f" 2>/dev/null)" = "PCH" ]; then
      n=$(echo "$f" | grep -oE 'card[0-9]+' | grep -oE '[0-9]+')
      CARD=$n; HW="/dev/snd/hwC${n}D0"; STATUS="/proc/asound/card${n}/pcm0p/sub0/status"
      return 0
    fi
  done
  return 1
}

echo 0 > /sys/module/snd_hda_intel/parameters/power_save 2>/dev/null

assert_speakers() {   # $1 = real DMA stream tag, $2 = real DMA format (hex)
  local tag=$1 fmt=$2
  v 0x0a 0x705 0x00                # converter D0
  v 0x0a 0x200 "$fmt"              # MATCH the live DMA format exactly
  v 0x0a 0x72d 0x03                # 4 channels
  v 0x0a 0x706 $(( tag<<4 ))       # bind the REAL controller tag
  v 0x24 0x703 0x01                # vendor proc on
  coef 00 00c4; coef 04 0c04; coef 05 1000; coef 03 0baa
  coef 02 003a; coef 36 0034; coef 19 8383; coef 1c 0010
  v 0x0a 0x70d 0x01; v 0x0a 0x70e 0x01; v 0x0a 0x70d 0x11   # DigEn
  v 0x1d 0x701 0x00; v 0x1d 0x707 0x40; v 0x1d 0x705 0x00   # speaker pin OUT
  v 0x01 0x716 0x09; v 0x01 0x717 0x01; v 0x01 0x715 0x01   # GPIO0 amp ON
}
amp_off() { v 0x01 0x715 0x00; }

last=""
while true; do
  if ! resolve_card; then sleep 2; continue; fi
  if grep -q "^state: RUNNING" "$STATUS" 2>/dev/null; then
    hp=$(rd 0x10 0xf09)
    if [ "$hp" = "0x0" ]; then                       # headphones unplugged -> speakers
      read -r tag fmt < <(python3 "$DMATAG" 2>/dev/null)
      if [ -n "$tag" ] && [ -n "$fmt" ]; then
        want=$(( tag<<4 )); cur=$(( $(rd 0x0a 0xf06) ))
        digi=$(rd 0x0a 0xf0d)
        if [ "$cur" != "$want" ] || [ "$digi" != "0x111" ] || [ "$tag:$fmt" != "$last" ]; then
          assert_speakers "$tag" "$fmt"; last="$tag:$fmt"
        fi
      fi
    else
      amp_off; last=""
    fi
  else
    last=""
  fi
  sleep 0.7
done
