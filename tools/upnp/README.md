# UPnP dev tools

Command-line tools for [`docs/UPNP.md`](../../docs/UPNP.md). Not part of the app target.

| Tool | What it is |
|---|---|
| `upnp-renderer-sim` | A fake UPnP AV **MediaRenderer** (profile: Expert 220). Develop the app's network output against it without the device. |
| `upnp-spike` | A **control point** that drives a renderer through a scripted test and logs everything. Its guided mode is what goes to the person next to the real Expert 220; the results replace the simulator's guesses. |
| `upnp-media-server` | A prototype of Audio Harbor as a **UPnP / DLNA music server**: shares a folder, so a player such as mconnect on the iPhone browses it and plays the files. |

```bash
cd tools/upnp
swift build -c release
.build/release/upnp-spike --make-test-files test-files   # the quiet test tones, if you want them as files
```

Both need the macOS **Local Network** permission for the terminal app (System Settings →
Privacy & Security → Local Network). Without it multicast is silently dropped: the sim gets no
M-SEARCH and the spike finds nothing. `--url` / `open <url>` in the spike skip SSDP.

## Simulator

```bash
.build/release/upnp-renderer-sim --uuid dev-1            # plays on the Mac's output
.build/release/upnp-renderer-sim --uuid dev-1 --silent   # clock only, no sound
```

- Answers SSDP (M-SEARCH, NOTIFY alive / byebye) and serves its description and SCPDs on port 49152.
- AVTransport: `SetAVTransportURI`, `SetNextAVTransportURI`, Play, Pause, Stop, Seek
  (`REL_TIME` / `ABS_TIME` / `TRACK_NR`), Get{Transport,Position,Media}Info, … with UPnP error codes
  (701, 711, 714, 716, 718 …) where a real renderer refuses.
- RenderingControl: volume 0–100, mute, VolumeDB. ConnectionManager: `GetProtocolInfo` sink list.
- GENA eventing (`LastChange`, SEQ in order) for AVTransport and RenderingControl.
- Fetches the whole file over HTTP, checks Content-Type against the sink list and the rate
  against `--max-rate`, decodes with AVFoundation. A file it cannot take ends in `STOPPED` with
  `ERROR_OCCURRED`, like a real renderer.
- A next track set with `SetNextAVTransportURI` is prefetched and starts without TRANSITIONING
  (the gapless path). Position comes from a clock, so `--silent` behaves the same.

Options: `--no-next`, `--no-events`, `--max-rate <Hz>`, `--start-delay <s>`, `--volume`,
`--sink-file <protocolinfo-sink.txt>`, `--name`, `--port`. `--uuid` keeps the UDN stable, so the
app's stored output pick finds it again after a restart.

Console while it runs: `status`, `vol <n>` (someone turns the knob → event), `mute`, `fail` (the
next load fails), `offline` / `online` (power off: byebye, connections dropped, state reset), `quit`.

**It is a model, not the device.** The defaults (formats, 192 kHz max, SetNext, events) are
assumptions. After a run on the real Expert 220, start it with
`--sink-file Ergebnis-…/protocolinfo-sink.txt` and the flags that match what the device did.

## Spike

**Guided test** (no options) — for the person next to the renderer. It makes its own test tones
(440 Hz, −20 dBFS, written as WAV and converted with macOS's `afconvert`), finds the Devialet,
then runs five steps: basics (play, pause, seek, volume −3 and back, SetNext, end of track), the
volume knob (does GetVolume / GENA follow the remote?), a gapless pair cut mid-cycle (with an
ear question), and 14 formats (FLAC 44.1–352.8 kHz, WAV incl. the 88.2 kHz / 24-bit the app
would stream for DSD in both header variants, AIFF, ALAC, AAC). German on the terminal,
everything else in `Ergebnis-<time>/` next to the program, zipped at the end. ctrl-C stops the
renderer and still zips. It keeps the Mac from idle sleep while it runs. If the renderer never
fetches a file it says so (firewall, VPN) and offers a retry.

```bash
.build/release/upnp-spike                                              # guided, finds the renderer
.build/release/upnp-spike --url http://127.0.0.1:49152/description.xml   # guided, against the sim
```

**Command prompt** (`-i`) — for poking at a renderer by hand: `auto <a> [<b>]`, `formats <folder>`,
`play`, `next`, `pause`, `resume`, `stop`, `seek`, `pos`, `vol`, `watch`, `subscribe`, `meta off`
(no DIDL-Lite), `mime <type>` (another Content-Type), `open <url>`, `discover`, `use <n>`.

Every SOAP call, every HTTP request the renderer makes with its headers and how many bytes it
read go to the log, with `summary.txt`, `formats.txt`, `protocolinfo-sink.txt` and the device's
description / SCPD XML next to it.

## Music server (prototype)

```bash
.build/release/upnp-media-server ~/Music
.build/release/upnp-media-server ~/Music --name "Audio Harbor" --port 49200
```

- Shares one folder as a MediaServer:1 (ContentDirectory + ConnectionManager). A player browses it
  folder by folder and plays the files itself; they go out untouched (FLAC, WAV, AIFF, ALAC / AAC,
  MP3, DSF / DFF), with `Range` for seeking.
- Title, artist, album and track number from the tags (FLAC's Vorbis comments read directly, the
  rest through AVFoundation, DSD by file name); covers from `cover` / `folder` / `front`
  (.jpg / .png) in the album folder.
- Object IDs are paths below the folder and the UDN comes from the folder's path, so players keep
  favourites across restarts.
- Only files inside the folder are served; `..` and symlinks out of it are refused. While it runs,
  anyone on the network can browse it: DLNA has no login.
- Keeps the Mac from idle sleep while it runs; ctrl-C announces the goodbye on the network.
- Not in the prototype: search, playlists, SACD ISO. Those come with the app's catalogue.

## Package for the tester

```bash
./make-tester-package.sh path/to/Anleitung.pdf
```

Builds `dist/Devialet-Test.zip`: the spike as `devialet-test` (universal arm64 + x86_64, macOS 12+,
ad-hoc signed) and the guide. The guide is the Claude Doc "Devialet-Test Anleitung", exported as
PDF. The binary is not notarized, so the start line in the guide clears the quarantine flag first:
`cd ~/Downloads/Devialet-Test && xattr -cr . && chmod +x devialet-test && ./devialet-test`.
