#!/usr/bin/env python3
# Read the HDA controller stream descriptors via the PCI BAR (resource0) to see
# which output stream is RUNNING and its stream TAG. Compares to what converter
# 0x0a is bound to (codec conv 0xf06 >> 4).
import mmap, os, struct, sys

RES = "/sys/bus/pci/devices/0000:00:1b.0/resource0"
fd = os.open(RES, os.O_RDWR | os.O_SYNC)
bar = mmap.mmap(fd, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)

def r8(o):  return bar[o]
def r16(o): return struct.unpack_from("<H", bar, o)[0]
def r32(o): return struct.unpack_from("<I", bar, o)[0]

gcap = r16(0x00)
iss = (gcap >> 8) & 0xf   # input streams
oss = (gcap >> 12) & 0xf  # output streams
bss = (gcap >> 3) & 0x1f  # bidir streams
gctl = r32(0x08)
print(f"GCAP=0x{gcap:04x}  input={iss} output={oss} bidir={bss}  GCTL=0x{gctl:08x} (CRST={gctl&1})")

# stream descriptors: input SDs first (iss), then output SDs (oss). SD base = 0x80, each 0x20.
# We care about output streams (they carry playback). Output SDs start after input SDs.
total = iss + oss + bss
print(f"\n{'SD#':<4}{'type':<7}{'offset':<8}{'CTL':<12}{'RUN':<5}{'TAG':<5}{'FMT':<8}{'LPIB'}")
for i in range(total):
    off = 0x80 + i * 0x20
    ctl = r32(off) & 0xffffff        # SDCTL is 3 bytes
    run = (ctl >> 1) & 1
    tag = (ctl >> 20) & 0xf
    fmt = r16(off + 0x12)
    lpib = r32(off + 0x04)
    if i < iss: typ = "in"
    elif i < iss + oss: typ = "out"
    else: typ = "bidir"
    mark = "  <== RUNNING" if run else ""
    print(f"{i:<4}{typ:<7}0x{off:<6x}0x{ctl:<10x}{run:<5}{tag:<5}0x{fmt:<6x}0x{lpib:x}{mark}")

bar.close(); os.close(fd)
