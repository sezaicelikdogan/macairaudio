#!/bin/bash
# Login-time setup for MacBook8,1 internal speakers: make the virtual stereo
# "Internal Speakers" sink the default and keep the raw hw node at full volume
# (so the virtual sink's volume slider is the one that controls loudness).
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

id_of() {  # $1 = node.name  -> prints the PipeWire node id
  pw-dump 2>/dev/null | python3 -c "
import json,sys
for o in json.load(sys.stdin):
    p=o.get('info',{}).get('props',{})
    if p.get('node.name')=='$1' and p.get('media.class')=='Audio/Sink':
        print(o['id']); break
"
}

# wait for the loopback nodes to exist after login
VSPK=""; RAW=""
for i in $(seq 1 30); do
  VSPK=$(id_of mb81.speakers); RAW=$(id_of mb81.hw.out)
  [ -n "$VSPK" ] && [ -n "$RAW" ] && break
  sleep 1
done
[ -z "$VSPK" ] && { echo "mb81: virtual speaker sink not found"; exit 0; }

wpctl set-volume "$RAW" 1.0 2>/dev/null          # raw node full; virtual sink controls loudness
wpctl set-default "$VSPK" 2>/dev/null            # apps -> Internal Speakers by default
echo "mb81: default sink -> Internal Speakers (id $VSPK), raw hw (id $RAW) at full volume"
