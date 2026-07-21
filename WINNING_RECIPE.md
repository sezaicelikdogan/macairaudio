# MacBook8,1 CS4208 internal-speaker WORKING recipe (verified audible 2026-07-21)

Hardware: MacBook8,1, Ubuntu 24.04, kernel 6.17.0-20. Codec CS4208 (0x10134208,
SSID 0x106b6400), card1 / hwC1D0 / PCI 00:1b.0. Custom driver
snd-hda-codec-cs420x.ko (juicecultus fork) installed in /lib/modules/.../updates/.

## THE KEY INSIGHT
Speakers are on the DIGITAL path: converter node 0x0a (TX1) -> digital speaker
pin 0x1d -> codec SP1 I2S/TDM master -> external Class-D amp gated by codec GPIO0.
The amp reads TDM slots that ONLY get clocked when the converter runs in
**4-CHANNEL** format (0x4013). Every prior attempt used 2-channel -> amp fed empty
slots -> silence. A 4-channel stream with stereo content in channels 0,1 = SOUND.

## EXACT WORKING SEQUENCE (verified audible)
Preconditions: a 4-channel DMA stream playing on card1 (stereo in ch0,ch1;
ch2,ch3 may be silent), HP jack unplugged. All verbs on hwC1D0.

1. converter 0x0a power D0:        0x0a 0x705 0x00
2. converter 0x0a format 0x4013:   0x0a SET_STREAM_FORMAT 0x4013   (44.1k/16bit/4ch)
3. converter 0x0a chan-count=4:    0x0a 0x72d 0x03
4. converter 0x0a stream id:       0x0a 0x706 (live_tag<<4)
5. vendor proc on:                 0x24 0x703 0x01
6. CIR coefs (0x24):  00=0x00c4  04=0x0c04  05=0x1000  03=0x0baa  02=0x003a
                      36=0x0034  19=0x8383  1c=0x0010
7. DigEn on 0x0a:     0x0a 0x70d 0x01 ; 0x0a 0x70e 0x01 ; 0x0a 0x70d 0x11
8. speaker pin 0x1d:  0x1d 0x701 0x00 (connect->0x0a) ; 0x1d 0x707 0x40 (OUT) ; 0x1d 0x705 0x00 (D0)
9. GPIO amp gate:     0x01 0x716 0x09 (mask) ; 0x01 0x717 0x01 (dir) ; 0x01 0x715 0x01 (GPIO0 HIGH = amp ON)

Verified state when audible: 0x0a DIGI1=0x111, conv=0x50 (tag 5), fmt=0x4013,
GPIO_DATA=0x09, pin 0x1d ctl=0x40, CIR[0x19]=0x8383.

## TDM slot map (from firmware CIR 0x04/0x05)
ch0->slot4, ch1->slot12, ch2->slot0, ch3->slot16. Stereo audio must land in
ch0 (L) and ch1 (R). (Currently both speakers sum ch0+ch1 -> "single tone"; L/R
separation is a refinement, not a blocker.)

## GPIO note (MacBook8,1-specific)
EFI ground truth: GPIO mask=0x09, dir=0x01 (only GPIO0 output, GPIO3 input),
GPIO0 HIGH = amp ON. The driver's play_a1534 uses MacBook9,1 values
(dir=0x31/mask=0x37) - bit0 is common so it still works, but 8,1 values are cleaner.

## WHAT'S NEEDED FOR PERMANENCE
(a) The digital converter 0x0a must run 4-channel whenever speakers are the output.
(b) Normal apps output 2ch stereo -> must be delivered as a 4ch stream (stereo in
    ch0,1) to card1. Either PipeWire outputs 4ch (upmix stereo->ch0,1) OR the
    driver presents the speaker PCM as 4ch.
(c) The driver's cs_4208_playback_pcm_hook currently does NOT fire (GPIO/DigEn stay
    0 on playback) - needs fixing so play_a1534 runs on PCM open, forced to 4ch,
    on the speaker path (ignore/patch the hp_pin_sense gate as needed).
