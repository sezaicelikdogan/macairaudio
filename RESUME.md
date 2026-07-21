# MacBook8,1 internal speakers on Linux — RESUME / STATUS

## Status: FULLY INSTALLED & PERMANENT (pending final reboot test)

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
