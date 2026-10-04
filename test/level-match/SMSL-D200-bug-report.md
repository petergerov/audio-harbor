Subject: SMSL D200 — louder at higher sample rates (USB)

Hello SMSL support,

My D200 plays the same file louder when it runs at a higher sample rate: about +6 dB at 88.2 kHz
and +12 dB at 192 kHz, compared with 44.1 kHz. It should be equally loud at every rate.

## How to reproduce (macOS, no extra software)

1. Open Audio MIDI Setup, select "SMSL USB AUDIO", and use it for sound output.
2. Set Format to 44,100 Hz. In Terminal, play the attached test file and measure the level:
   afplay -t 7 "Level test PCM 44k1 24bit 1kHz -6dBFS.flac"
3. Set Format to 88,200 Hz, play the same file again, and measure.
   afplay -t 7 "Level test PCM 44k1 24bit 1kHz -6dBFS.flac"
4. Keep every volume setting the same.

## My results (same file, −6 dBFS 1 kHz sine)

| D200 rate | Level |
|---|---|
| 44.1 / 48 kHz | 0 dB (reference) |
| 88.2 kHz | +6 dB |
| 96 kHz | +3 dB |
| 176.4 kHz | +11 dB |
| 192 kHz | +12 dB |

Every digital filter on the D200 gives the same result. The same files over the MacBook's own
headphone output play equally loud at every rate, so the problem is in the D200.

## Details

- Firmware: SMSLD200MCUFWv104.zip
- Output: RCA, [DAC mode with fixed output or preamp mode], volume 0 (Max)
- Mac: macOS 26.5.2, USB

Is this a known issue, and is there a firmware fix?

Best regards,
Petar Gerov
