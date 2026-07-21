#!/bin/bash
# MacBook8,1 internal-speaker auto-enable daemon (runs as root via systemd).
# Finds the CS4208 card by its STABLE id (PCH) — ALSA card NUMBERS are not stable
# across boots (they can swap with HDMI). Whenever audio plays and headphones are
# unplugged, asserts the 4-channel/16-bit digital speaker path. Idempotent.
v()  { hda-verb "$HW" "$1" "$2" "$3" >/dev/null 2>&1; }
rd() { hda-verb "$HW" "$1" "$2" 0 2>/dev/null | grep -oE '0x[0-9a-f]+$' | tail -1; }
coef() { v 0x24 0x500 0x$1; v 0x24 0x400 0x$2; }

# resolve the CS4208 card number from its stable id (PCH) -> sets CARD, HW, STATUS
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

assert_speakers() {   # $1 = stream tag, $2 = live format from converter 0x02
  local tag=$1 fmt02=$2
  local spk_fmt=$(( (fmt02 & 0x7F00) | 0x0013 ))   # keep rate bits, force 16-bit + 4ch
  v 0x0a 0x705 0x00
  v 0x0a 0x200 $(printf '0x%x' $spk_fmt)
  v 0x0a 0x72d 0x03
  v 0x0a 0x706 $(( tag<<4 ))
  v 0x24 0x703 0x01
  coef 00 00c4; coef 04 0c04; coef 05 1000; coef 03 0baa
  coef 02 003a; coef 36 0034; coef 19 8383; coef 1c 0010
  v 0x0a 0x70d 0x01; v 0x0a 0x70e 0x01; v 0x0a 0x70d 0x11
  v 0x1d 0x701 0x00; v 0x1d 0x707 0x40; v 0x1d 0x705 0x00
  v 0x01 0x716 0x09; v 0x01 0x717 0x01; v 0x01 0x715 0x01
}
amp_off() { v 0x01 0x715 0x00; }

last_tag=""
while true; do
  if ! resolve_card; then sleep 2; continue; fi     # CS4208 not present yet
  if grep -q "^state: RUNNING" "$STATUS" 2>/dev/null; then
    hp=$(rd 0x10 0xf09)
    if [ "$hp" = "0x0" ]; then
      tagreg=$(rd 0x02 0xf06)
      if [ -n "$tagreg" ] && [ "$tagreg" != "0x0" ]; then
        tag=$(( tagreg >> 4 )); fmt02=$(rd 0x02 0xa00)
        digi=$(rd 0x0a 0xf0d); cur=$(rd 0x0a 0xf06)
        if [ "$digi" != "0x111" ] || [ "$cur" != "$tagreg" ] || [ "$tagreg" != "$last_tag" ]; then
          assert_speakers "$tag" "$(( fmt02 ))"; last_tag="$tagreg"
        fi
      fi
    else
      amp_off; last_tag=""
    fi
  else
    last_tag=""
  fi
  sleep 0.7
done
