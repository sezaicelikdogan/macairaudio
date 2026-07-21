# macairaudio — internal speakers on Linux for the 12″ MacBook (MacBook8,1)

Making the **internal speakers** work on Linux for the 2015 12″ Retina MacBook
(**MacBook8,1**, board A1534) — a machine whose speakers have been silent on Linux
since it shipped. The Cirrus **CS4208** codec drives them over a **digital I2S/TDM**
path to an external Class‑D amplifier, and no mainline or community driver ever
figured out how to feed it. This project does.

> Status: **the speakers produce sound** (verified: tones + music). Packaging it to
> survive every reboot/kernel‑upgrade is in progress — see **[Status](#status)**.

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

This recipe was reverse‑engineered from the EFI **boot‑chime** code inside the Mac's
SPI flash (the firmware plays the chime through these same speakers at every boot),
plus a post‑chime codec capture. The exact verb sequence is in
[`WINNING_RECIPE.md`](WINNING_RECIPE.md).

## How the fix is built

Three cooperating pieces:

1. **Driver** (`mbdrv/`, DKMS) — the juicecultus CS4208 fork, built and
   **DKMS‑registered** so it auto‑rebuilds on every kernel upgrade. It exposes the
   4‑channel PCM on `hw:CARD=PCH,0`.
2. **PipeWire** (`config/pipewire`, or the flat `*.conf` here) — a raw ALSA sink
   locked to **S16LE / 4ch / 48 kHz** (`mb81.hw.out`), fronted by a virtual **stereo**
   sink `Internal Speakers` (so the GNOME volume slider works normally) whose audio
   is up‑mixed to 4 channels by a loopback.
3. **Codec daemon** (`mb81-speaker-assert.sh` + `mb81-speakers.service`) — a root
   service that asserts the digital speaker path (converter `0x0a` 16‑bit/4ch + DigEn
   + CIR coefficients + GPIO0 amp) whenever audio plays and headphones are unplugged.
   It resolves the card by its **stable id** (`PCH`), because ALSA card **numbers**
   swap with HDMI across boots.

A **safety net** (`mb81-safety.sh`) auto‑restores normal audio if the speaker config
ever fails at boot, and `panic-restore-audio.sh` is a manual escape hatch — a bad
boot can never leave you without audio.

## Install

> Needs: DKMS, build tools, kernel headers, `alsa-tools` (`hda-verb`), a `sudo -A`
> askpass, PipeWire (Ubuntu 24.04 default).

```bash
git clone https://github.com/sezaicelikdogan/macairaudio ~/mb81-speaker-fix
cd ~/mb81-speaker-fix

# 1. build + DKMS-register the 4-channel driver (survives kernel upgrades)
bash install-driver.sh        # build + install for the running kernel
#    (DKMS registration: see rebuild-driver.sh / mbdrv/dkms.conf)

# 2. codec daemon + power_save=0 + resume hook
bash install-service.sh

# 3. PipeWire configs + user services are under ~/.config (see config/ notes)
```

If a kernel upgrade ever breaks it: `bash rebuild-driver.sh`.

## Status

- ✅ Root cause solved; **speakers produce clean sound** (tones + music), with a
  working volume slider, on kernel **6.17**.
- ⚠️ Kernel **7.0** regression under investigation: the card renumbers (1→0, fixed
  by using the stable `PCH` id) **and** the driver's per‑open hook routes the stream
  differently, currently leaving the digital path silent even with an identical
  register state. Debugging in progress.
- 🔜 Follow‑ups: true stereo L/R separation (both speakers currently sum ch0+ch1);
  headphone auto‑switch verification.

## Repo layout

| Path | What |
|------|------|
| `WINNING_RECIPE.md` | exact codec verb sequence that produces sound |
| `RESUME.md` | detailed working notes / current state / recovery commands |
| `mbdrv/` | the DKMS driver source (patched CS4208) |
| `mb81-speaker-assert.sh` | the codec daemon (asserts the digital speaker path) |
| `mb81-setup.sh` | login setup (default sink) |
| `mb81-safety.sh` / `panic-restore-audio.sh` | fail‑safe recovery |
| `install-driver.sh` / `install-service.sh` / `rebuild-driver.sh` | installers |
| `*.conf` / `*.service` | PipeWire + systemd units |

The firmware dump used to extract the recipe is **not** included (it's Apple's
copyrighted firmware and contains a machine serial number). Dump your own with
`sudo dd if=/dev/mtd0ro of=bios.bin`.

## Credits

Built on the CS4208 work of **leifliddy**, **davidjo**, and **juicecultus**. The
MacBook8,1‑specific digital‑path recipe (4‑channel / 16‑bit / firmware coefficients)
was reverse‑engineered for this project.

## License

GPL‑2.0 (the driver is a Linux kernel module derived from GPL sources).
