# UPnP / DLNA — network players and library sharing

**Goal:** The Mac plays to a UPnP / DLNA network renderer (first target: Devialet Expert 220) the
way it plays to a USB DAC: pick it as the output device, press play. The Mac stays the player and
library; the renderer only pulls audio over HTTP. The iPhone remote keeps working unchanged.

**Status:** built (Mac), on `develop`. Network output: Settings → Output → Device (**This Host** /
**Network Players**); radios **Wi‑Fi friendly** / **Full** / **DSD, SACD, DoP**. Library sharing:
Settings → Sharing. Not yet checked on the real Expert 220 — the guided test in `tools/upnp` is
ready. How it is built: [ARCHITECTURE.md](ARCHITECTURE.md#network-output-upnp-renderer-mac).

Not multi-room, not OpenHome (later, if ever).

---

## How it works

```
Audio Harbor (Mac)                                   Renderer (Devialet)
 ├─ SSDP discovery  ── M-SEARCH MediaRenderer:1 ──▶  answers with description URL
 ├─ Control point   ── SOAP AVTransport ──────────▶  SetAVTransportURI / Play / Pause / Seek
 │                  ── SOAP RenderingControl ─────▶  Get/SetVolume
 │                  ◀─ GetPositionInfo / GetTransportInfo (polled)
 └─ HTTP media server ◀── GET /t/<token> (Range) ──  pulls the audio
```

Three pieces, all macOS-only (`#if os(macOS)`), under `AudioHarbor/UPnP/` (shared with the music server):

| Type | Job |
|---|---|
| `SSDPBrowser` | UDP multicast M-SEARCH + NOTIFY listener (Network.framework, BSD socket fallback). Fetches each device description, keeps renderers that have AVTransport + RenderingControl. Publishes `[UPnPRenderer]` (UDN, friendly name, control URLs, base URL). Drops a renderer on `ssdp:byebye` or expired `max-age`. |
| `UPnPControlPoint` | `actor`. SOAP calls over `URLSession` (AVTransport, RenderingControl, ConnectionManager.GetProtocolInfo). Small hand-written XML builder + `XMLParser` for responses; no dependency. DIDL-Lite metadata (title, artist, album, artwork URL, `res` with protocolInfo, duration, sample rate, bit depth). |
| `MediaHTTPServer` | `NWListener` on a fixed-preferred port (like the remote). Serves one-time tokens → stream sources. `Range` support, `Content-Length`, `HEAD`, DLNA headers (`transferMode.dlna.org: Streaming`, `contentFeatures.dlna.org`). URL host = the Mac's IP on the interface the renderer was found on. |
| `UPnPPlaybackEngine` | Conforms to `PlaybackEngine`. `load` registers the track with the HTTP server and sends `SetAVTransportURI`; `play/pause/seek/stop` map to AVTransport; `currentTime` interpolates between 1 s `GetPositionInfo` polls; track end = transport goes `STOPPED` after `PLAYING` near the end (or `SetNext` advanced). Meters stay at 0. |
| `RoutingPlaybackEngine` | Conforms to `PlaybackEngine`, owns `CoreAudioPlaybackEngine` + `UPnPPlaybackEngine`, forwards to the one the picked output belongs to. `AppModel` passes it to `PlaybackService` — `PlaybackService` stays almost untouched. |

### Output device model

Renderers appear in the existing output picker. `OutputDevice` gets a `kind` (`.local` / `.network`);
network UIDs are `upnp:<UDN>` so the stored pick (`DefaultsKey.outputDevice`) survives restarts and
comes back like a replugged DAC. `OutputStatus.devices` = Core Audio devices + live renderers.
`setOutputDevice(uid:)` already stops and lets `PlaybackService` reload at the same position —
switching between DAC and renderer reuses that path.

For a network output: Shared / Exclusive / DoP are replaced by network radios (**Wi‑Fi friendly** /
**Full** / **DSD, SACD, DoP** when the player lists DSD). The plugin rack is not applied. Volume
binds to RenderingControl so `outputVolume` and the iPhone volume buttons keep working.

### What gets sent

Decided per track from the renderer's `GetProtocolInfo` sink list and the network radio:

| Source | Sent as |
|---|---|
| FLAC / WAV / AIFF / ALAC / MP3 / AAC the renderer lists | **The file bytes, untouched** — bit-perfect, the renderer decodes. Seeking via `Range`. |
| A PCM format it does not list | Decoded and streamed as WAV (24-bit, source rate). |
| DSF / DFF / SACD with **DSD, SACD, DoP** and the player lists that type | **The file untouched** (SACD as extracted DFF). Path: `DSD · Network`. |
| DSF / DFF / SACD with **Full** (or Auto with no native type) | `DSDToPCMConverter` → 88.2 kHz / 24-bit WAV, `DSDConversion.gain` applied. |
| DSF / DFF / SACD with **Wi‑Fi friendly** | Live 44.1 kHz / 16-bit PCM WAV (~1.4 Mbit/s). FLAC and other listed formats stay untouched. |

Generated WAV has a computed `Content-Length` (`header + frames × blockAlign`), so a `Range` request
maps to a frame and the decoder seeks there; seek via the renderer works the same as for files.

### Bandwidth (Wi‑Fi)

With **Full**, DSF / SACD / DFF become **24-bit PCM WAV** at typically **88.2 kHz stereo**
(decimation keeps the PCM rate ≤ 96 kHz), unless **DSD, SACD, DoP** sends the file untouched.
With **Wi‑Fi friendly**, DSD is always 44.1 kHz / 16-bit PCM.

#### What Audio Harbor actually streams

| Source | What goes over HTTP | Payload bitrate | ≈ Data rate |
|---|---|---|---|
| DSD64 / SACD stereo (2.8224 MHz) | WAV 88.2 kHz · 24-bit · 2 ch | **4.23 Mbit/s** | **~0.50 MB/s** |
| DSD128 stereo | same ~88.2 kHz WAV | **4.23 Mbit/s** | **~0.50 MB/s** |
| DSD256 stereo | same ~88.2 kHz WAV | **4.23 Mbit/s** | **~0.50 MB/s** |

`88200 × 2 × 24 = 4 233 600 bit/s`. HTTP/TCP overhead and especially **Range** re-requests (the
renderer often aborts and restarts) add roughly **+20–50 %** on a flaky link — budget
**~6–8 Mbit/s stable**, not only the 4.2.

#### If the file were sent untouched (not our path)

| Format | Bitrate (stereo) |
|---|---|
| DSD64 / SACD | **~5.6 Mbit/s** |
| DSD128 | **~11.3 Mbit/s** |
| DSD256 | **~22.6 Mbit/s** |

#### Context

| Stream | Typical bitrate |
|---|---|
| CD WAV (44.1 kHz · 16-bit · 2 ch) | ~1.4 Mbit/s |
| FLAC passthrough | often 0.5–2 Mbit/s |
| DSD → WAV (our network path) | **~4.2 Mbit/s** |

Dropouts on weak Wi‑Fi are usually the link dipping under ~5–8 Mbit/s plus Range retries, not
“DSD needing more than SACD raw.” Wired Ethernet or solid 5 GHz helps; otherwise Settings →
**Wi‑Fi friendly** converts only DSD/SACD to CD-rate PCM (~1.4 Mbit/s).

### Gapless

`SetNextAVTransportURI` for the next track in play order. If a renderer refuses it once, that is
remembered for the renderer and the next track is set on `STOPPED` — a short gap, documented, not hidden.

---

## Phases

| # | Step | Size | Done when |
|---|---|---|---|
| 0a | **Simulator** (`tools/upnp/upnp-renderer-sim`, done): a fake MediaRenderer with an Expert 220 profile — SSDP, AVTransport incl. SetNext, RenderingControl, GENA, plays on the Mac or `--silent`. Phases 1–5 are built against it. | done | Spike passes `auto` + `formats` against it |
| 0b | **Spike on the real Expert 220** (`tools/upnp/upnp-spike`, done; the device is not on our network, so it runs where the amplifier is): a guided five-step test packaged as `Devialet-Test.zip` (`tools/upnp/make-tester-package.sh`) with a German guide (Claude Doc "Devialet-Test Anleitung", PDF in the zip). Formats, seek, volume and knob, SetNext, end of track, gapless by ear, events. Results go into this file and into the simulator flags (`--sink-file`, `--no-next` …). | 1 session on site | We know the format list and the quirks; go / no-go |
| 1 | `SSDPBrowser` + renderers in the Settings output picker (no playback yet) | 2 d | Devialet listed, survives its power cycle — **done** (discovery + picker; play still local until Phase 3) |
| 2 | `MediaHTTPServer` with file passthrough + `Range`, tokens, interface-correct URLs | 2 d | `curl` against it from another machine — **done** |
| 3 | `UPnPControlPoint` + `UPnPPlaybackEngine` + `RoutingPlaybackEngine`; play / pause / seek / volume / position / track end / queue advance | 3–4 d | Album plays through on the Devialet from Mac and iPhone remote — **done** (file passthrough; DSD/WAV transcode = Phase 4) |
| 4 | WAV transcode stream: DSD → PCM, unsupported PCM, SACD ISO virtual tracks | 2 d | DSF and SACD ISO play, seek works — **done** |
| 5 | Gapless (`SetNext`), DIDL metadata + artwork URL, renderer lost / back (error in Deck, stored pick returns) | 2 d | Live album gapless if the device can — **done** |
| 6 | Polish: keep Mac awake while streaming (`ProcessInfo.beginActivity`), docs (ARCHITECTURE, settings.md, FAQ), PRODUCT.md scope change | 1 d | **done** |

**Total ≈ 2–2.5 weeks.** Development runs against the simulator; the spike on the real device only has to happen before release. Phases 0–3 are the useful core; 4–5 can ship later.

---

## Music server (DLNA)

**In the app:** Settings → Sharing turns the Mac into a UPnP / DLNA music server. A player on the
iPhone (e.g. mconnect) browses Albums · Artists · Directories · Playlists · Labels and plays the
files there, or sends them on to any renderer it knows. How it is built:
[ARCHITECTURE.md](ARCHITECTURE.md#music-server-dlna-mac). The folder prototype stays in
`tools/upnp/upnp-media-server`.

Open: search (ContentDirectory Search over the FTS index), GENA events for SystemUpdateID, DFF
chapter tracks (each chapter served as a DFF of its own).

## Platform notes

- **Sandbox:** `network.client` / `network.server` already in the entitlements — enough for SSDP
  and the HTTP server. Files are served from the existing security-scoped bookmarks.
- **Local network privacy (macOS 15+):** the first multicast send triggers the prompt;
  `NSLocalNetworkUsageDescription` names network players and sharing. A denial leaves the list empty
  and shows a hint under Device.
- **Firewall:** the renderer connects *in* to the Mac's HTTP port — the macOS firewall prompt
  appears once, same as for the remote listener.
- **Sleep:** Core Audio playback keeps the Mac awake; network play holds
  `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` while the transport is `PLAYING`.
- **iOS:** nothing — the iPhone is a remote. `outputName` already shows the renderer's name.

## Testing

| Layer | Approach |
|---|---|
| SSDP / SOAP / DIDL parsing | Planned: unit tests with captured Devialet responses as fixtures (no test target yet) |
| HTTP server, Range, WAV header math | Planned: byte-exact unit tests |
| Engine state machine | Planned: unit tests against a fake control point |
| End to end | `upnp-renderer-sim` on the dev Mac: discovery, play, seek, volume knob, gapless, `fail`, `offline` / `online` |
| Real device | Manual checklist on the Expert 220: formats, seek, volume, gapless, power cycle, Wi-Fi drop |

## Licensing

Part of the existing one-time unlock (`com.gerov.audioharbor.unlock`) — no extra product, no
extra price. Network output is playback like any other: it goes through
`PlaybackService.allowPlayback()` / `LicenseService.canPlay`, so it works during the 7-day trial and
after the unlock, and stops when the trial has ended without one. No separate gate, no badge.

## Open questions

1. Devialet specifics (rates, DSD, gapless, volume scale) — answered by the spike.
2. OpenHome (playlists on the renderer, Mac can sleep) — only if someone asks; not in this plan.
3. Discovery starts at launch, so macOS asks for Local Network access on first launch even without a
   network player. Start it when the output picker opens or a network pick is stored?
4. WAV header for 24-bit: plain PCM tag today; the spike checks whether the Devialet wants
   WAVE_FORMAT_EXTENSIBLE.
