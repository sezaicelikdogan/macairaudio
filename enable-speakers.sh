#!/bin/bash
# Re-enable the internal-speaker PipeWire configs (after safety-net/panic disabled them).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
D=~/mb81-speaker-fix
for f in 50-mb81-speakers-out.conf 51-mb81-loopback.conf; do
  [ -f "$D/pw-configs-autodisabled/$f" ] && mv "$D/pw-configs-autodisabled/$f" ~/.config/pipewire/pipewire.conf.d/
  [ -f "$D/pw-configs/$f" ] && cp "$D/pw-configs/$f" ~/.config/pipewire/pipewire.conf.d/
done
systemctl --user restart pipewire pipewire-pulse wireplumber
sleep 3; bash "$D/mb81-setup.sh"
echo "speakers re-enabled."
