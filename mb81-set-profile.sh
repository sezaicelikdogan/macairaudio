#!/bin/bash
# Set the CS4208 analog card to Surround 4.0 (needed for the internal-speaker
# 4-channel digital path). Runs at login as a user service. Idempotent.
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
CARD_NAME="alsa_card.pci-0000_00_1b.0"
WANT="output:analog-surround-40+input:analog-stereo"

# wait for the device to be present after login
DEV=""
for i in $(seq 1 30); do
  DEV=$(pw-cli ls Device 2>/dev/null | awk '/\tid [0-9]+,/{id=$2} /'"$CARD_NAME"'/{gsub(/,/,"",id); print id; exit}')
  [ -n "$DEV" ] && break
  sleep 1
done
[ -z "$DEV" ] && { echo "mb81: CS4208 device not found"; exit 0; }

# find the surround-40 profile index dynamically (fallback to 16)
IDX=$(pw-cli enum-params "$DEV" EnumProfile 2>/dev/null \
      | grep -iE "index|description|name" \
      | grep -B2 "analog-surround-40+input:analog-stereo" \
      | grep -oE 'Int [0-9]+' | grep -oE '[0-9]+' | head -1)
[ -z "$IDX" ] && IDX=16

wpctl set-profile "$DEV" "$IDX" 2>/dev/null && echo "mb81: set $CARD_NAME -> profile $IDX ($WANT)"
