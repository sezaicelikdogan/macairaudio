# Ubuntu 24.04 on the 12″ MacBook (2015, MacBook8,1) — Complete Guide

A practical, tested guide to installing **Ubuntu 24.04 LTS** on the 12″ Retina
MacBook (**MacBook8,1**, board A1534) and fixing everything that doesn't work out
of the box — including the **internal speakers**, silent on Linux for 10 years and
solved for the first time by this project.

Everything below was worked out and verified on a real MacBook8,1 running
Ubuntu 24.04 (GNOME 46, PipeWire, HWE kernels 6.17 → 7.0).

## What you get

| Hardware | Out of the box | After this guide |
|---|---|---|
| Keyboard + trackpad (internal, SPI) | ⚠️ randomly dead on some boots | ✅ reliable every boot |
| Wi‑Fi (BCM4350) | ✅ works | ✅ |
| Bluetooth (BCM4350C0 UART) | ❌ dead on most boots | ✅ works, devices auto‑reconnect |
| **Internal speakers** | ❌ **silent (10‑year‑old bug, "unsupported")** | ✅ **working, with volume control** |
| Headphone jack + microphone | ✅ works | ✅ |
| Suspend / resume (lid) | ✅ works | ✅ (audio survives via resume hook) |
| Webcam (FaceTime HD) | ❌ needs out‑of‑tree driver | ❌ not covered here (see [facetimehd](https://github.com/patjak/facetimehd)) |
| Stereo L/R separation | — | ⚠️ both speakers play summed stereo (mono‑ish; open item) |

## Step 0 — Before you start

- Any 12″ MacBook **8,1** (2015). Check in macOS: Apple menu → About This Mac, or on
  Linux: `sudo dmidecode -s system-product-name`.
- A USB‑C adapter/hub for a USB stick (the machine has a single USB‑C port).
- **Back up** anything you care about. Decide: dual‑boot (keep macOS, shrink its
  partition) or wipe. Keeping a small macOS partition is handy for firmware updates.
- Build a normal Ubuntu 24.04 USB installer
  ([official instructions](https://ubuntu.com/tutorials/create-a-usb-stick-on-ubuntu)).

## Step 1 — Install Ubuntu

1. Plug in the USB stick, power on holding **Option (⌥)**, pick the yellow
   **EFI Boot** entry.
2. Install Ubuntu 24.04 normally (the installer's keyboard and trackpad work —
   the input bug is intermittent and only affects some boots).
3. Boot into your new system. If the **keyboard/trackpad are dead on a boot**,
   power off and on again — then apply Step 2 immediately, it removes this
   lottery permanently.

Wi‑Fi works out of the box (`brcmfmac`). Bluetooth will look dead — that's Step 3.

## Step 2 — Fix the keyboard + trackpad (random dead boots)

**Symptom:** on some cold boots, the internal keyboard and trackpad don't work at
all; power‑cycling 2–3× "fixes" it.
**Cause:** the keyboard/trackpad are SPI devices (`applespi`). When the broken
DesignWare LPSS DMA driver (`dw_dmac`) wins a module‑load race, every SPI transfer
times out. Blacklisting it forces the always‑working PIO path.

First grab this repo — **all remaining steps use it**:

```bash
git clone https://github.com/sezaicelikdogan/macairaudio
cd macairaudio
bash extras/keyboard/install-keyboard-fix.sh
```

Reboot. Every boot should now log the healthy marker:
`journalctl -k | grep 'no DMA channels available, using PIO'`

## Step 3 — Fix Bluetooth

**Symptom:** `hci0` exists but is dead (address `00:00:00:00:00:00`), dmesg shows
`command 0xfc18 tx timeout` / `Reset failed (-110)`. The GNOME Bluetooth toggle is
missing and BLE devices (mice…) never auto‑reconnect.
**Cause:** a cold‑boot init race in the UART transport. A warm re‑probe of the
same device always succeeds — so a boot service *rebinds the serdev driver*
(~1 s) instead of the slow module reload. A per‑user session daemon then keeps a
connection armed for your paired devices, because this chip's ROM firmware
corrupts some BLE advertising reports, which makes BlueZ's normal auto‑reconnect
unreliable.

```bash
bash extras/bluetooth/install-bluetooth.sh
```

Pair your devices once (GNOME Settings or `bluetoothctl`). From then on: move the
mouse → it connects within a few seconds. (A Bluetooth icon in the top bar only
appears when a device is *connected* — that's GNOME 46 design, not a bug.)

There is **no firmware patch file** for this chip (`brcm/BCM.hcd` "not found" is
cosmetic): Apple itself runs it on ROM firmware. Don't chase the .hcd — it doesn't
exist, even in Apple's own Boot Camp drivers (we checked).

## Step 4 — Fix the internal speakers (the big one)

**Symptom:** headphones work, speakers are completely silent on every kernel; all
existing CS4208 community drivers mark this model "not supported".
**Cause & discovery:** the speakers hang off a **digital I2S/TDM path** with an
external amplifier that only produces sound for a *4‑channel, 16‑bit* stream with
vendor coefficients and an amp‑enable GPIO — a recipe reverse‑engineered from the
Mac's own EFI boot‑chime code. Full story below in
[The speaker story](#macairaudio--internal-speakers-on-linux-for-the-12-macbook-macbook81).

```bash
sudo apt install dkms build-essential linux-headers-$(uname -r) alsa-tools
bash install-driver.sh     # build + DKMS-register the patched CS4208 driver
bash install-service.sh    # codec daemon + power_save off + resume hook
bash mb81-setup.sh         # PipeWire sinks + login services + default sink
```

(The first driver build downloads matching kernel source from kernel.org,
~150 MB — it's reused for later kernel upgrades, which DKMS handles automatically.)

Reboot, open YouTube, enjoy the first sound these speakers ever made on Linux.
The GNOME volume slider works normally. Plugging headphones mutes the speaker amp.

If a kernel upgrade ever breaks audio: `bash rebuild-driver.sh` (DKMS should
handle it automatically; this is the manual fallback). If a boot ever comes up
with broken audio config: `bash panic-restore-audio.sh` restores stock audio.

## Step 5 — Quirks you should know (so you don't debug ghosts)

- **BLE mice transmit only when moved.** After boot or sleep, the mouse connects
  a second or two after *you move the mouse itself* — not before, and moving the
  trackpad does nothing. If a mouse ever seems completely dead, toggle its power
  switch: after ~15 min of failed attempts these mice stop advertising entirely.
- **Rare Bluetooth drop under heavy load.** This fanless machine thermal‑throttles;
  a long CPU stall can starve the BT UART and kill the link. It self‑heals on the
  next mouse movement. Do **not** try raising the LE supervision timeout to fix
  this — this chip's ROM firmware **silently fails all connections** with a larger
  timeout (we learned the hard way; details in `RESUME.md`).
- **The macOS boot chime** plays at power‑on — that's firmware, before Linux, and
  it's normal (it's also *how the speaker recipe was discovered*).
- ALSA card **numbers** swap between boots (HDMI vs codec). Everything in this
  project uses the stable id `hw:CARD=PCH` — do the same in your own configs.

## Troubleshooting quick table

| Problem | First command |
|---|---|
| Keyboard/trackpad dead this boot | power‑cycle, then check Step 2 is installed |
| Bluetooth dead | `systemctl status fix-macbook-bluetooth` and `journalctl -b \| grep -i hci0` |
| Mouse won't reconnect | move *the mouse*; toggle its power switch; `journalctl --user -b \| grep 'mb81-bt]'` |
| No speaker sound | `systemctl status mb81-speakers`; then `bash rebuild-driver.sh` after kernel upgrades |
| Audio totally broken | `bash panic-restore-audio.sh` |

Everything deeper: [`RESUME.md`](RESUME.md) (full working notes, recovery
commands, and the debugging history of every fix above).

---

# macairaudio — internal speakers on Linux for the 12″ MacBook (MacBook8,1)

Making the **internal speakers** work on Linux for the 2015 12″ Retina MacBook
(**MacBook8,1**, board A1534) — a machine whose speakers have been silent on Linux
since it shipped. The Cirrus **CS4208** codec drives them over a **digital I2S/TDM**
path to an external Class‑D amplifier, and no mainline or community driver ever
figured out how to feed it. This project does.

> Status: **SOLVED.** Speakers work automatically (music, video, volume slider),
> survive reboot, power‑off, and kernel upgrades (DKMS). Verified on kernels 6.17
> and 7.0.

## The problem

On the MacBook8,1 the CS4208's headphone jack and microphone work out of the box,
but the **internal speakers are dead** on every Linux kernel (open upstream since
2016: kernel bugzilla #110561). The community CS4208 driver
([leifliddy](https://github.com/leifliddy/macbook12-audio-driver) /
[davidjo](https://github.com/davidjo/snd_hda_macbookpro) /
[juicecultus](https://github.com/juicecultus/macbook12-audio-driver)) explicitly
marks the **8,1 as "not supported"** — it targets the 9,1/10,1 which use the same
codec but a different speaker topology.

## The discovery (why it was silent for 10 years)

The speakers are **not** on the analog DAC path. They are on a **digital** path:

```
CS4208 converter node 0x0a (TX1, digital)  ->  digital pin 0x1d (fixed speaker)
   ->  codec SP1 I2S/TDM master port  ->  external Class-D amp (gated by codec GPIO0)
```

Getting sound out requires **all** of the following at once — miss any one and it's
silent (or noise):

1. **4 channels.** The amp only clocks its TDM slots when converter `0x0a` runs in
   **4‑channel** format. A 2‑channel stream = empty slots = silence. Stereo audio
   must land in channels 0 and 1 (TDM slots 4 and 12).
2. **16‑bit.** The amp only accepts **16‑bit** TDM data. 24/32‑bit (S32_LE, PipeWire's
   default) misaligns the slots = silence; a rate/bit **mismatch** between the codec
   converter and the DMA = **noise**.
3. **The vendor CIR coefficients** on node `0x24` (extracted from the Mac's own
   firmware — see [`WINNING_RECIPE.md`](WINNING_RECIPE.md)).
4. **DigEn** — `SET_DIGI_CONVERT_1 = 0x11` on `0x0a` (the digital‑transmitter enable).
5. **GPIO0 high** — gates the external amplifier on.
6. **The custom driver loaded** — the stock `cs420x` only exposes a 2‑channel PCM;
   the patched driver exposes the 4‑channel digital path via converter `0x0a`.
7. **The live DMA stream tag.** The HDA controller assigns each playback DMA a
   stream **tag dynamically** (it varies per open!), and converter `0x0a` must be
   bound to *that exact tag* or it receives silence. This was the final missing
   piece: `mb81-dmatag.py` reads the running stream's tag + format directly from
   the controller MMIO and the daemon binds `0x0a` to it.

This recipe was reverse‑engineered from the EFI **boot‑chime** code inside the Mac's
SPI flash (the firmware plays the chime through these same speakers at every boot),
plus a post‑chime codec capture. The exact verb sequence is in
[`WINNING_RECIPE.md`](WINNING_RECIPE.md).

## How the fix is built

Three cooperating pieces:

1. **Driver** (`mbdrv/`, DKMS) — the juicecultus CS4208 fork, built and
   **DKMS‑registered** so it auto‑rebuilds on every kernel upgrade. It exposes the
   4‑channel PCM on `hw:CARD=PCH,0`.
2. **PipeWire** — a raw ALSA sink locked to **S16LE / 4ch / 48 kHz** (`mb81.hw.out`),
   fronted by a virtual **stereo** sink `Internal Speakers` (so the GNOME volume
   slider works normally) whose audio is up‑mixed to 4 channels by a loopback.
3. **Codec daemon** (`mb81-speaker-assert.sh` + `mb81-speakers.service`) — a root
   service that asserts the digital speaker path (converter `0x0a` 16‑bit/4ch + DigEn
   + CIR coefficients + GPIO0 amp, bound to the **live DMA stream tag**) whenever
   audio plays and headphones are unplugged. It resolves the card by its **stable
   id** (`PCH`), because ALSA card **numbers** swap with HDMI across boots.

A **safety net** (`mb81-safety.sh`) auto‑restores normal audio if the speaker config
ever fails at boot, and `panic-restore-audio.sh` is a manual escape hatch — a bad
boot can never leave you without audio.

## Repo layout

| Path | What |
|------|------|
| `extras/keyboard/` | keyboard/trackpad fix (dw_dmac blacklist) + installer |
| `extras/bluetooth/` | Bluetooth boot heal + session daemon + installer |
| `WINNING_RECIPE.md` | exact codec verb sequence that produces sound |
| `RESUME.md` | detailed working notes / current state / recovery commands |
| `mbdrv/` | the DKMS driver source (patched CS4208) |
| `mb81-speaker-assert.sh` | the codec daemon (asserts the digital speaker path) |
| `mb81-dmatag.py` | reads the live DMA stream tag/format from controller MMIO |
| `mb81-setup.sh` | login setup (default sink) |
| `mb81-safety.sh` / `panic-restore-audio.sh` | fail‑safe recovery |
| `install-driver.sh` / `install-service.sh` / `rebuild-driver.sh` | installers |
| `*.conf` / `*.service` | PipeWire + systemd units |

The firmware dump used to extract the recipe is **not** included (it's Apple's
copyrighted firmware and contains a machine serial number). Dump your own with
`sudo dd if=/dev/mtd0ro of=bios.bin` (needs the Intel SPI‑NOR MTD driver; only
relevant if you want to explore the firmware — not needed for any install step).

## Credits

Built on the CS4208 work of **leifliddy**, **davidjo**, and **juicecultus**. The
MacBook8,1‑specific digital‑path recipe (4‑channel / 16‑bit / firmware coefficients
/ dynamic stream‑tag binding) was reverse‑engineered for this project.

## License

GPL‑2.0 (the driver is a Linux kernel module derived from GPL sources).
