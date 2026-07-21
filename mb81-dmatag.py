#!/usr/bin/env python3
# Print the RUNNING output-stream's HDA tag and format from the controller, by
# reading the PCI BAR (resource0) directly. Output: "<tag> <fmt_hex>" or nothing.
# The CS4208 speaker converter 0x0a must be bound to THIS tag (it is dynamic).
import mmap, os, struct, sys, glob

# find the CS4208 (PCH) controller PCI address dynamically
pci = "0000:00:1b.0"
for c in glob.glob("/sys/class/sound/card*/id"):
    try:
        if open(c).read().strip() == "PCH":
            dev = os.path.dirname(c) + "/device"
            pci = os.path.basename(os.path.realpath(dev))
            break
    except Exception:
        pass
res = f"/sys/bus/pci/devices/{pci}/resource0"

try:
    fd = os.open(res, os.O_RDWR | os.O_SYNC)
except Exception:
    sys.exit(0)
bar = mmap.mmap(fd, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)
gcap = struct.unpack_from("<H", bar, 0x00)[0]
iss = (gcap >> 8) & 0xf
oss = (gcap >> 12) & 0xf
bss = (gcap >> 3) & 0x1f
# output stream descriptors come after input ones
for i in range(iss, iss + oss + bss):
    off = 0x80 + i * 0x20
    ctl = struct.unpack_from("<I", bar, off)[0] & 0xffffff
    run = (ctl >> 1) & 1
    if run:
        tag = (ctl >> 20) & 0xf
        fmt = struct.unpack_from("<H", bar, off + 0x12)[0]
        print(f"{tag} 0x{fmt:04x}")
        break
bar.close(); os.close(fd)
