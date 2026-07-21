#!/bin/bash
# MacBook8,1 Bluetooth session daemon (BCM4350C0) — v4, PERSISTENT.
#
# PROVEN FACTS (gnome-shell 46 source extraction + journal forensics of 3 test boots):
#  * GNOME 46 top-bar BT icon: `visible = nConnectedDevices > 0` — shows ONLY when a
#    device is connected. Icon missing == mouse not connected. One symptom.
#  * GNOME 46 QS TOGGLE: gated on gsd-rfkill's BluetoothHasAirplaneMode via a proxy
#    with an init race — a value already true when the shell's proxy initializes is
#    never noticed (no g-properties-changed fires for init-loaded values). A
#    gsd-rfkill restart AFTER the shell is up forces owner-change -> GetAll -> full
#    changed dict -> toggle re-syncs. Restarting BEFORE the shell is up re-creates
#    the race (v3 did this: it beat gnome-shell by 1-3s on every test boot).
#  * The mouse (Pebble M350s, BLE) transmits ONLY when physically moved. On all 3
#    test boots it connected within ~1s of its radio first being heard. The perceived
#    "50-60s delay" was simply when the MOUSE (not trackpad) was next moved/awake.
#  * BlueZ's native auto-reconnect is unreliable here: the unpatched BCM4350C0
#    corrupts some advertising reports ("unknown advertising packet type" in dmesg,
#    UART runs at fallback baudrate). A directly-armed connect completes in hardware
#    and works ~instantly, so this daemon keeps one armed at all times.
#  * Boot-3's mid-session drop: link died silently under softirq/thermal pressure
#    (NOHZ tick-stop + intel_powerclamp lines bracket it); the armed loop re-caught
#    the mouse the moment it advertised again. Nothing to fix but re-arm speed.
#
# STRUCTURE: main process = the forever connect loop (arming starts ~4s after
# session start). The QS-toggle fix runs in a background child of the same cgroup
# (service stays active forever, so systemd reaps nothing early — the v2 lesson).

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}
log() { echo "[mb81-bt] $*"; }

# ---- 1. wait for a SETTLED controller (past any serdev rebind) ------------------
# Pre-rebind stale controller reports address 00:00:00:00:00:00; require a real
# address + Powered, held 4 consecutive seconds. Up to 120s.
settled=0
addr=""
for _ in $(seq 1 120); do
  out=$(bluetoothctl show 2>/dev/null)
  addr=$(printf '%s\n' "$out" | grep -oE 'Controller [0-9A-F:]{17}' | awk '{print $2}')
  if printf '%s\n' "$out" | grep -q "Powered: yes" \
     && [ -n "$addr" ] && [ "$addr" != "00:00:00:00:00:00" ]; then
    settled=$((settled + 1))
    [ "$settled" -ge 4 ] && break
  else
    settled=0
  fi
  sleep 1
done
if [ "$settled" -lt 4 ]; then
  log "adapter never settled (addr=${addr:-none}) — continuing to connect loop anyway"
else
  log "adapter settled: $addr"
fi

# ---- 2. QS TOGGLE fix, in background, only after gnome-shell owns its bus name --
# Restarting gsd-rfkill before the shell's rfkill proxy exists re-creates the init
# race; wait for org.gnome.Shell + grace so the owner-change lands on a live proxy.
(
  for _ in $(seq 1 60); do
    gdbus call --session --dest org.freedesktop.DBus \
      --object-path /org/freedesktop/DBus \
      --method org.freedesktop.DBus.NameHasOwner org.gnome.Shell 2>/dev/null \
      | grep -q true && break
    sleep 2
  done
  sleep 6
  for attempt in 1 2 3; do
    systemctl --user restart org.gnome.SettingsDaemon.Rfkill.target 2>/dev/null
    sleep 2
    has=$(gdbus call --session --dest org.gnome.SettingsDaemon.Rfkill \
          --object-path /org/gnome/SettingsDaemon/Rfkill \
          --method org.freedesktop.DBus.Properties.Get \
          org.gnome.SettingsDaemon.Rfkill BluetoothHasAirplaneMode 2>/dev/null)
    case "$has" in
      *true*) log "QS toggle re-synced post-shell (attempt $attempt)"; break ;;
      *)      log "QS toggle not ready (got: ${has:-none}), retry $attempt"; sleep 3 ;;
    esac
  done
) &

# ---- 3. MAIN: forever keep a connect armed for every disconnected paired device -
# While disconnected: a direct LE connect is pending most of every cycle; the
# controller completes it in hardware the instant the device advertises (= the
# moment the mouse itself is moved). Logs connect AND disconnect transitions.
log "entering persistent connect loop"
announced=""
while true; do
  all_ok=1
  for dev in $(bluetoothctl devices Paired 2>/dev/null | awk '{print $2}'); do
    if bluetoothctl info "$dev" 2>/dev/null | grep -q "Connected: yes"; then
      case "$announced" in *"$dev"*) ;; *) log "device $dev connected"; announced="$announced $dev";; esac
      continue
    fi
    all_ok=0
    case "$announced" in *"$dev"*) log "device $dev DISCONNECTED — re-arming"; announced=${announced//" $dev"/};; esac
    # log each DISTINCT failure reason once, so silent-failure regressions
    # (like the supervision-timeout incident) show up in the journal
    err=$(timeout 20 bluetoothctl connect "$dev" 2>&1 | tail -1)
    if [ -n "$err" ] && [ "$err" != "$last_err" ] \
       && ! bluetoothctl info "$dev" 2>/dev/null | grep -q "Connected: yes"; then
      log "connect attempt ($dev): $err"; last_err="$err"
    fi
  done
  if [ "$all_ok" = 1 ]; then sleep 10; else sleep 1; fi
done
