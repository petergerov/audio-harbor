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
| Shared soul | Same engine philosophy on Mac and iPhone; Mac leads on DAC depth |

---

## MVP (v1.0) — Ship this first

**Goal:** Daily-driver local player on Mac; capable companion on iOS.

### Playback
- [x] Gapless PCM playback
- [x] Formats: FLAC, ALAC, WAV, AIFF, AAC/M4A, MP3
- [x] DSD: DSF (+ DFF if time); DoP on supported Mac DACs; PCM fallback when needed
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

### UI / UX
- [x] SwiftUI multiplatform shell (Mac + iPhone; iPad adaptive)
- [x] Three primary surfaces: Library · Now Playing · Settings
- [x] Large artwork Now Playing, minimal chrome
- [x] Dark, quiet visual language (no dashboard clutter)
- [x] Keyboard shortcuts on Mac (space, arrows, ⌘O)

### Settings (MVP-thin)
- [x] Output device (Mac)
- [x] Exclusive mode on/off
- [x] DSD: DoP vs convert-to-PCM
- [x] Library folders
- [x] ReplayGain off / track / album (optional if low cost)

### Explicitly out of MVP
- Video, SACD ISO, converter suite
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
- iPad optimized layout
- Mac menu bar mini player + notch-friendly compact mode
- Continuity: handoff queue Mac ↔ iPhone (same library roots when possible)
- CarPlay (iOS) — later, carefully

### Ecosystem (later)
- Optional Qobuz/Tidal *if* it doesn’t dilute local-first identity
- Remote control from iPhone → Mac engine
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
MVP Mac  →  MVP iOS companion  →  Pro audio depth  →  Polish & Continuity
```

Mac first: Exclusive mode and DAC behavior define the brand. iOS ships the same library language with platform-honest audio limits.
