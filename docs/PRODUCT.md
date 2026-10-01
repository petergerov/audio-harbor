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
- [x] DSD: DoP in Output DoP, convert-to-PCM otherwise (no separate DSD setting)
- [x] Library folders
- [x] ReplayGain off / track / album (optional if low cost)

### Explicitly out of MVP
- Video, converter suite, CUE sheets, multi-channel SACD, DST encoder / `.dst` container
- DLNA / Chromecast / AirPlay multi-room as product focus
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

### Platform Pro
- [x] iPhone remote for the Mac engine — Bonjour + pairing code; browse, search, queue, transport; DAC hardware volume from the slider and the iPhone's volume buttons (ships with Mac 1.1)
- Listen on iPhone — the Mac streams to the paired iPhone on the home network (see below)
- [x] iPad as a remote too — two columns (Now + Queue · Search/Browse), iPhone layout in narrow Split View
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
