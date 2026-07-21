#!/bin/bash
# User-side setup for MacBook8,1 internal speakers. Idempotent — safe to run
# any time, and it also runs at every login (via the unit it installs itself):
#   1. installs the PipeWire configs (raw 4ch/16bit sink + virtual stereo
#      "Internal Speakers" sink) into ~/.config/pipewire/pipewire.conf.d/
#   2. installs + enables its own login unit and the safety-net unit
#   3. makes "Internal Speakers" the default sink, raw hw node at full volume
#      (so the virtual sink's volume slider is the one that controls loudness)
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 1. PipeWire configs (restart PipeWire only when something changed) --------
PWDIR="$HOME/.config/pipewire/pipewire.conf.d"
mkdir -p "$PWDIR"
changed=0
for f in "$DIR"/pw-configs/*.conf; do
  b="$(basename "$f")"
  if ! cmp -s "$f" "$PWDIR/$b"; then cp "$f" "$PWDIR/$b"; changed=1; fi
done
if [ "$changed" = 1 ]; then
  echo "mb81: PipeWire configs installed -> restarting PipeWire"
  systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null
  sleep 2
fi

# ---- 2. login unit (this script) + safety-net unit -----------------------------
UDIR="$HOME/.config/systemd/user"
mkdir -p "$UDIR"
cat > "$UDIR/mb81-setup.service" <<EOF
[Unit]
Description=MacBook8,1 speakers: set Internal Speakers as default sink
After=wireplumber.service pipewire.service
Wants=wireplumber.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 3
ExecStart=$DIR/mb81-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=default.target
EOF
cat > "$UDIR/mb81-safety.service" <<EOF
[Unit]
Description=MacBook8,1 speaker safety net (recover audio if speaker config crashes PipeWire)
# deliberately NO dependency on pipewire — must run even if pipewire failed

[Service]
Type=oneshot
ExecStart=$DIR/mb81-safety.sh

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable mb81-setup.service mb81-safety.service 2>/dev/null

# ---- 3. default sink + volumes -------------------------------------------------
id_of() {  # $1 = node.name  -> prints the PipeWire node id
  pw-dump 2>/dev/null | python3 -c "
import json,sys
for o in json.load(sys.stdin):
    p=o.get('info',{}).get('props',{})
    if p.get('node.name')=='$1' and p.get('media.class')=='Audio/Sink':
        print(o['id']); break
"
}

VSPK=""; RAW=""
for i in $(seq 1 30); do
  VSPK=$(id_of mb81.speakers); RAW=$(id_of mb81.hw.out)
  [ -n "$VSPK" ] && [ -n "$RAW" ] && break
  sleep 1
done
[ -z "$VSPK" ] && { echo "mb81: virtual speaker sink not found (is the driver installed and the CS4208 card present?)"; exit 0; }

wpctl set-volume "$RAW" 1.0 2>/dev/null          # raw node full; virtual sink controls loudness
wpctl set-default "$VSPK" 2>/dev/null            # apps -> Internal Speakers by default
echo "mb81: default sink -> Internal Speakers (id $VSPK), raw hw (id $RAW) at full volume"
