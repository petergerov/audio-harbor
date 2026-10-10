# Audio Harbor — Product Scope

**Positioning:** A simple, beautiful audiophile player for macOS and iOS. Bit-perfect where it matters. No feature maze.

**Promise:** Open folder → hear truth. Fewer controls, better defaults, exceptional playback.

**Inspiration gap:** Pine Player Pro is powerful but crowded. Audio Harbor ships less surface area and a cleaner path from library to DAC.

---

## North Star

| Principle | Meaning |
|---|---|
| One job | Play local high-res audio correctly |
| Honest quality | Prefer bit-perfect over marketing upsampling |
| Calm UI | Brand + library + now playing — nothing else competing |
| Shared soul | One product on Mac and iPhone: the Mac plays on the DAC, the iPhone steers it |

---

## MVP (v1.0) — Ship this first

**Goal:** Daily-driver local player on Mac. The iPhone follows as its remote (Mac 1.1 + iOS).

### Playback
- [x] Gapless PCM playback
- [x] Formats: FLAC, ALAC, WAV, AIFF, AAC/M4A, MP3
- [x] DSD: DSF, DFF, SACD ISO stereo (including DST); DoP on supported Mac DACs; PCM fallback when needed
- [x] Automatic sample-rate switching to match the file (Mac)
- [x] Exclusive / bit-perfect output mode (Mac)
- [x] Queue + play next / play later
- [x] Lock screen / Now Playing / media keys

### Library
- [x] Add folders (watch for changes on Mac)
- [x] Fast scan + metadata (title, artist, album, year, track #, artwork)
- [x] Browse by Album / Artist / Folder
- [x] Search
- [x] Simple playlists (local)
- [x] M3U / M3U8 playlist import and export
- [x] Add a directory, album, artist or the Deck queue to a playlist or label (right-click)
- [x] Album artist grouping; untagged compilations stay one album
- [x] Cover art from the file, else from the album folder (`cover` / `folder` / `front`)

### UI / UX
- [x] SwiftUI multiplatform shell (Mac + iPhone; iPad adaptive)
- [x] Three primary surfaces: Library · Now Playing · Settings
- [x] Large artwork Now Playing, minimal chrome
- [x] Dark, quiet visual language (no dashboard clutter)
- [x] Keyboard shortcuts on Mac (Space, ⌘← / ⌘→, ⌘O; ⌘1 Catalogue, ⌘2 Playlists, ⌘3 Deck, ⌘, Settings)
- [x] Play from the Catalogue without leaving it; ⌘-click, *Play and Show Deck* or the mini player open the Deck

### Settings (MVP-thin)
- [x] Output device (Mac)
- [x] Exclusive mode on/off
- [x] DSD: DoP in Output DoP, convert-to-PCM otherwise (no DSD strategy setting)
- [x] DSD as PCM level: 0 / +3 / +6 dB (default +3), so converted DSD plays about as loud as DoP
- [x] Library folders
- [x] ReplayGain off / track / album (optional if low cost)

### Explicitly out of MVP
- Video, converter suite, CUE sheets, multi-channel SACD, DST encoder / `.dst` container
- DLNA / Chromecast / AirPlay multi-room as product focus (one UPnP renderer as an output and a DLNA music server are built, see Platform Pro)
- Streaming services (Qobuz, Tidal, etc.)
- Heavy parametric EQ / DSP playground
- Cloud sync / accounts
- Upsampling marketing modes (768 kHz etc.)

### Success criteria (MVP)
1. Bit-perfect FLAC → external DAC on Mac (verified with device sample-rate match)
2. DSF plays via DoP on a known-good DAC, or clean PCM fallback
3. New user plays music in under 60 seconds (add folder → play)
4. UI feels simpler than Pine within first session

---

## Pro (v1.x → v2) — Paid depth, still simple

Ship only after MVP feels effortless. Pro adds power *behind* the same calm UI.

### Audio Pro
- High-quality offline resampler (opt-in; never default over bit-perfect)
- Parametric EQ + headphone profiles (clearly labeled as non-bit-perfect)
- **User AUv3 inserts (iOS + Mac) and classic AU (Mac) on Shared output** — forces Shared · FX; Exclusive/DoP remain the bit-perfect path with an empty rack
- Crossfade (optional; off by default for audiophile path)
- Cue sheet support
- APE / WavPack / Opus if demand warrants
- Multichannel / surround path (honest about mixer involvement)

### Library Pro
- Smart playlists
- Batch metadata editor
- Duplicate detection
- NAS / network volumes polish (SMB reliability)
- iCloud / folder sync of playlists (not the audio files)

#### External DLNA servers as a library source — not planned

**Decision:** Audio Harbor does not mount DLNA / UPnP media servers (NAS, MinimServer, …) as a library.
Mount the NAS share (SMB) in macOS and add it as a directory instead.

**Why:**
- Nearly every DLNA server runs on a NAS that also shares files. As a directory the share gets
  everything: full tags, artwork, search, playlists, labels, bit-perfect Exclusive / DoP, DSD and SACD ISO.
  Through DLNA only what the server exposes: its own tree, often thin tags, often no DSD or converted files.
- The engine plays files. Exclusive, DoP and SACD extraction read the file itself; an HTTP stream would
  have to be downloaded and cached first — a lot of work for what a mounted share already gives.
- A second library source with its own rules is the feature maze the North Star rules out. SMB
  reliability (above) is the better investment.

**When it would make sense:** a server that offers only DLNA and no file share (rare), or someone who
wants a server's own browsing (MinimServer's tag tree) — a niche.

**The one interesting case:** Audio Harbor as a pure control point — the network player (the Devialet)
pulls straight from the NAS, so the Mac could sleep. mconnect / BubbleUPnP do that today (NAS as source,
Devialet as player).

**If it ever comes:** browse-only in its own view, play only on a network player. The local engine
never learns HTTP sources.

**Variant: the iPhone app as the control point — also not planned.** The iPhone would browse the
DLNA server and tell the Devialet what to play; the Mac could sleep and the app would still play nothing
itself. It fits "the iPhone steers", but two things stop it:

- **The queue lives in the app.** A plain UPnP AV renderer such as the Devialet knows only the current and
  the next track; the control point has to hand over the third. iOS suspends the app shortly after it
  leaves the screen, so the music stops after at most two tracks. Apps like mconnect keep themselves alive
  with silent background audio — App Review dislikes that. OpenHome renderers (Linn …) keep the queue
  themselves; the Devialet is not known to.
- **SSDP on iOS needs the multicast entitlement** (`com.apple.developer.networking.multicast`), granted by
  Apple on request, not by default.

And it competes with mconnect, BubbleUPnP and others at their own game; Audio Harbor's strength is the
library on the Mac. The robust path already exists: the Mac steers and serves (stays awake, long queues,
gapless SetNext), the iPhone is the remote. NAS straight to the Devialet without the Mac: mconnect.

### Platform Pro
- [x] iPhone remote for the Mac engine — Bonjour + pairing code; browse, search, queue, transport; DAC hardware volume from the slider and the iPhone's volume buttons (ships with Mac 1.1)
- Listen on iPhone — the Mac streams to the paired iPhone on the home network (see below)
- [x] iPad as a remote too — the same layout as the iPhone, centred
- [x] Playlists and labels from the remote — long-press a song: Add to Playlist… / Labels…, tap to put it in or take it out; playing a song or Play all stays in the list and marks the playing row (Mac + iOS 1.1.1, protocol 2)
- [x] Search on the remote like the Mac's catalogue search — Dirs across every directory, Albums / Artists / Lists with a matching song (Mac + iOS 1.1.1)
- Play to a UPnP renderer (Mac) — a network streamer / amplifier such as the Devialet Expert shows up as an output device; files untouched where the player takes them, DSD as PCM, Wi‑Fi mode; part of the one-time unlock, no extra charge — built for the next release (see [`UPNP.md`](UPNP.md))
- Share the library as a UPnP / DLNA music server (Mac) — Settings → Sharing; a player such as mconnect browses it and plays on the iPhone; part of the one-time unlock — built for the next release (see [`UPNP.md`](UPNP.md))
- Mac menu bar mini player + notch-friendly compact mode
- Continuity: handoff queue Mac ↔ iPhone (same library roots when possible)
- CarPlay (iOS) — later, carefully

#### Listen on iPhone (LAN)

**Why:** The library stays on the Mac (or NAS); you take it to the bedroom, kitchen or garden on headphones. The remote already browses, searches and queues the Mac's catalogue, so a stream is cheaper than a standalone iPhone player with its own library, file access and sync.

**Scope:**
- Home network only, over the existing pairing (token). No relay, no port forwarding, no TLS — leaving the LAN is a different project.
- The Mac sends the original file; the iPhone decodes with `AVAudioEngine`. No transcoding, except DSF / DFF / SACD ISO → PCM on the Mac.
- The Mac stays silent while the iPhone plays; one output at a time.
- Gapless across tracks, buffering against Wi-Fi jitter, background audio, Now Playing / lock screen, interruptions (calls).
- Bandwidth is not a constraint: 24/192 stereo ≈ 9.2 Mbit/s.

**Honesty:** Labelled “Listen on iPhone”, never bit-perfect. The iOS mixer may resample, Bluetooth is lossy. The Mac + DAC stays the bit-perfect path.

**Open questions:**
- Transfer whole files ahead vs. chunked streaming (seek, storage, gapless).
- Hand back to the Mac mid-track (ties into Continuity).
- App Review: the iPhone becomes a player — background audio needs fresh justification.

**When:** After Pro audio depth. Covers or precedes a standalone iPhone player.

### Ecosystem (later)
- Optional Qobuz/Tidal *if* it doesn’t dilute local-first identity
- Export / convert as a separate “Tools” area — never in the main path

### Monetization sketch
| Tier | Contents |
|---|---|
| Free / Lite | Library + PCM formats + basic player |
| Pro (one-time or sub) | DSD/DoP, exclusive mode, EQ, advanced library, mini player |
| Keep UX identical | Pro unlocks depth; does not add chrome |

---

## Competitive frame

| App | Strength | Audio Harbor angle |
|---|---|---|
| Pine Player Pro | Format/DAC kitchen sink | Simpler path, better UI |
| Audirvana | Pro audio pedigree | Lighter, modern SwiftUI, Apple-native |
| Roon | Ecosystem / discovery | Local-first, no server tax |
| Music.app | Free, integrated | Real hi-res + DSD + exclusive |
| VOX / Neutron | Mobile hi-res | Shared Mac+iOS product, calmer UX |

---

## Release sequencing

```
Mac 1.0  →  Mac 1.1 + iPhone remote  →  Pro audio depth  →  Polish & Continuity
```

Mac first: Exclusive mode and DAC behavior define the brand. The iPhone joins as the Mac's remote, free, under the same App Store listing (Universal Purchase). A player on iPhone / iPad stays a later option; streaming from the Mac (“Listen on iPhone”) is the likely first step. Submission steps: [`APP_STORE_SUBMISSION.md`](../APP_STORE_SUBMISSION.md) § 11.
