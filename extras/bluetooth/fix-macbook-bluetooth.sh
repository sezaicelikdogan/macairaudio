#!/bin/bash
# Fast fix for the BCM4350C0 UART Bluetooth cold-init failure on MacBook8,1.
#
# Root cause: on cold boot, serdev pre-sets the *operating* UART baud rate
# before hu->setup() runs. The chip's first Broadcom vendor command
# (0xfc18 UPDATE_BAUDRATE) then times out (-110), and the follow-up HCI reset
# times out (-110), so hci0 is registered with a null BD address (unhealthy).
# A WARM re-probe of the SAME serdev device succeeds in ~1s (the LPSS UART /
# chip are already open at a working speed).
#
# We therefore rebind the serdev driver (echo to unbind/bind) instead of
# reloading the hci_uart *module*. The module-reload path (modprobe -r/modprobe)
# takes ~30s on kernel 7.0 because module_init re-probes synchronously; the
# serdev rebind runs only bcm_probe()/bcm_setup() and completes in ~1-2s.

DRV=/sys/bus/serial/drivers/hci_uart_bcm
DEV=serial0-0

bd_addr()   { hciconfig hci0 2>/dev/null | sed -n 's/.*BD Address: \([0-9A-F:]*\).*/\1/p'; }
is_healthy(){ local a; a=$(bd_addr); [[ -n "$a" && "$a" != "00:00:00:00:00:00" ]]; }


# 1. Wait (max ~15s) for the cold probe to bind the serdev device.
for _ in $(seq 1 30); do
    [[ -e "$DRV/$DEV" ]] && break
    sleep 0.5
done

# 2. Already healthy (cold init happened to succeed)? Done.
if is_healthy; then
    echo "hci0 healthy on cold init, no rebind needed"
    exit 0
fi

# 3. Warm re-probe via serdev rebind, up to 3 attempts.
#    The unbind write blocks until any in-flight (doomed) cold probe releases
#    the device, so this self-synchronises with the failing init.
for attempt in 1 2 3; do
    echo "hci0 unhealthy, rebinding serdev (attempt $attempt)"
    echo "$DEV" > "$DRV/unbind" 2>/dev/null
    sleep 0.5
    echo "$DEV" > "$DRV/bind"   2>/dev/null
    for _ in $(seq 1 20); do            # wait up to 10s for warm probe
        is_healthy && { echo "hci0 healthy after rebind (attempt $attempt)"; exit 0; }
        sleep 0.5
    done
done

is_healthy && exit 0
echo "hci0 still unhealthy after 3 rebinds" >&2
exit 1
