# MacBook8,1 internal speakers on Linux — RESUME / STATUS

## Status: kernel 7.0 REGRESSION under investigation (worked on 6.17)

### >>> CURRENT BLOCKER (2026-07-21, kernel 7.0.0-28) <<<
Speakers WORKED earlier this session on kernel 6.17. A reboot upgraded to kernel
**7.0.0-28** and broke them. Two things changed:
1. ALSA card RENUMBERED: CS4208 went card 1 -> card 0. FIXED: everything now uses
   the stable id `hw:CARD=PCH` and the daemon resolves the card by id "PCH".
   (This also fixed a PipeWire boot CRASH — the old hw:1,0 pointed at HDMI.)
2. ROUTING CHANGED: on 7.0 the driver routes the analog PCM (hw:PCH,0) ENTIRELY to
   converter 0x0a (conv=0x10 tag 1, fmt 0x4013=44.1k), analog DACs 0x02-0x05 idle/D3.
   On 6.17 it routed to 0x02 (the daemon read tag from 0x02 and mirror-bound 0x0a).
   Even matching format (44.1k) + full assert (DigEn, CIR, GPIO0) = STILL NO SOUND,
   despite the register state looking identical to when it worked.
DISABLED play_a1534() + cs_4208_playback_pcm_hook in cs420x.c (rebuilt via DKMS) to
stop the driver fighting the daemon — routing still goes to 0x0a, still silent.
A diagnostic workflow (run id wf_3f9f721d-9bb) was launched to root-cause (codec
state diff vs EFI capture, controller DMA tag via MMIO, driver amp-init analysis) but
STOPPED before completing — RE-RUN it to continue: leading hypotheses are (a) a
one-time amp-init lost by disabling play_a1534, (b) controller DMA tag != 0x0a binding.

### NOW ON GITHUB: github.com/sezaicelikdogan/macairaudio (push token cached 2h; ROTATE it)

### If speakers needed urgently: boot kernel 6.17.0-20 (GRUB Advanced options) — worked there.

---
## (earlier) Status: FULLY INSTALLED & PERMANENT (pending final reboot test)

Internal speakers WORK (YouTube, music, tones, volume slider) — a 10-year-old
kernel bug on an "unsupported" model. Everything below is installed and boot-persistent.

## Root cause (all found)
Speakers are on the codec DIGITAL path: CS4208 converter 0x0a -> digital pin 0x1d
-> SP1 I2S/TDM -> external Class-D amp gated by GPIO0. Needs: (1) 4-CHANNEL, (2)
16-BIT stream (24/32-bit = silent; mismatch = noise); stereo in ch0,1. AND the
CUSTOM DRIVER must be loaded (stock cs420x only exposes a 2ch PCM; the fork exposes
4ch via converter 0x0a). The reboot that "lost sound" was a KERNEL UPGRADE
(6.17 -> 7.0) orphaning the hand-copied driver — now fixed with DKMS.

## What is INSTALLED (all persistent)
1. DRIVER via DKMS: `macbook12-audio-driver/0.1` (AUTOINSTALL=yes -> auto-rebuilds
   on every kernel upgrade). Source /usr/src/macbook12-audio-driver-0.1. Verify:
   `dkms status` -> installed;  `modinfo -n snd_hda_codec_cs420x` -> .../updates/dkms/...
2. ROOT DAEMON: /etc/systemd/system/mb81-speakers.service (enabled) runs
   /usr/local/sbin/mb81-speaker-assert.sh — asserts converter 0x0a (16-bit/4ch +
   DigEn + CIR + GPIO0 amp) whenever audio plays; HP auto-mute.
3. /etc/modprobe.d/mb81-speaker.conf (power_save=0) + resume hook
   /usr/lib/systemd/system-sleep/mb81-speaker.
4. PIPEWIRE: ~/.config/pipewire/pipewire.conf.d/50-mb81-speakers-out.conf (raw
   S16/4ch node "mb81.hw.out" on hw:1,0, suspend-timeout=0) + 51-mb81-loopback.conf
   (virtual STEREO sink "mb81.speakers" = GNOME volume slider, loopback upmixes to 4ch).
5. USER SERVICE ~/.config/systemd/user/mb81-setup.service (enabled) sets default
   sink = Internal Speakers + raw node full volume.

## ARCHITECTURE
apps -> "Internal Speakers" (stereo virtual sink, GNOME volume) -> loopback (2->4ch)
-> "mb81.hw.out" (S16/4ch on hw:1,0) -> root daemon asserts codec 0x0a -> amp.

## IF SPEAKERS BREAK
- After a KERNEL UPGRADE (DKMS should auto-handle, but if not): `bash ~/mb81-speaker-fix/rebuild-driver.sh` then `sudo systemctl restart mb81-speakers.service`.
- If chain is 2ch after boot: `systemctl --user restart pipewire wireplumber; bash ~/mb81-speaker-fix/mb81-setup.sh` (loopback relinks 4ch on fresh start).
- Verify chain: play audio (no headphones); `grep channels /proc/asound/card1/pcm0p/sub0/hw_params` -> 4; `sudo hda-verb /dev/snd/hwC1D0 0x0a 0xf0d 0` -> 0x111.

## FOLLOW-UPS (not blockers)
- Headphones: daemon mutes speaker amp on HP-plug; verify audio routes to HP jack.
- Stereo L/R separation (both speakers currently sum ch0+ch1).

## Files: ~/mb81-speaker-fix/ (install-driver.sh, install-service.sh, rebuild-driver.sh,
## mb81-setup.sh, mb81-speaker-assert.sh, WINNING_RECIPE.md, mbdrv/ = driver+DKMS source, bios.bin)
