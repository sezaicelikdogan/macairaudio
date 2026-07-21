#!/bin/bash
# EMERGENCY: instantly restore normal audio (disable speaker configs + restart PipeWire).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
mkdir -p ~/mb81-speaker-fix/pw-configs-autodisabled
mv ~/.config/pipewire/pipewire.conf.d/50-mb81-speakers-out.conf ~/mb81-speaker-fix/pw-configs-autodisabled/ 2>/dev/null
mv ~/.config/pipewire/pipewire.conf.d/51-mb81-loopback.conf ~/mb81-speaker-fix/pw-configs-autodisabled/ 2>/dev/null
systemctl --user reset-failed pipewire pipewire-pulse wireplumber 2>/dev/null
systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null
echo "normal audio restored (speakers disabled). Re-enable with: bash ~/mb81-speaker-fix/enable-speakers.sh"
