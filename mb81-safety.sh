#!/bin/bash
# Safety net: if the speaker PipeWire config ever crashes PipeWire at boot, this
# disables the config and restores normal audio automatically (so a bad boot can
# never strand the user without audio / volume / the GNOME menu).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
CONF="$HOME/.config/pipewire/pipewire.conf.d"
STASH="$HOME/mb81-speaker-fix/pw-configs-autodisabled"

sleep 15   # give PipeWire time to settle after login

if ! systemctl --user is-active --quiet pipewire; then
  logger -t mb81-safety "PipeWire not active after boot — disabling mb81 speaker configs and recovering normal audio"
  mkdir -p "$STASH"
  mv "$CONF/50-mb81-speakers-out.conf" "$STASH/" 2>/dev/null
  mv "$CONF/51-mb81-loopback.conf" "$STASH/" 2>/dev/null
  systemctl --user reset-failed pipewire pipewire-pulse wireplumber 2>/dev/null
  systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null
  logger -t mb81-safety "recovery done — speakers disabled this boot; run ~/mb81-speaker-fix/enable-speakers.sh to retry"
fi
