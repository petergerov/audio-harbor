# Audio Harbor — Technical Architecture

## Platforms & stack

| Layer | Choice |
|---|---|
| UI | SwiftUI (multiplatform) |
| Language | Swift 5.10+ / Swift 6 concurrency where safe |
| App shape | One shared target via XcodeGen → iOS + macOS |
| Persistence | SQLite+FTS5 catalogue in Application Support; portable library file for playlists/labels (see below) |
| Metadata | AVFoundation + TagLib-style fallback later for exotic tags |
| Audio | Core Audio / AVAudioEngine; custom DSD path |
| Min OS | iOS 17 · macOS 14 (bump if needed for APIs) |

**Why SwiftUI multiplatform:** One product language, one navigation model, shared domain/audio protocols. Platform differences live behind adapters, not forked apps.

---

## High-level modules

```
┌─────────────────────────────────────────────────────────┐
│                        App Shell                        │
│         (AudioHarborApp · RootView · Navigation · DI)           │
└───────────────┬─────────────────────┬───────────────────┘
                │                     │
┌───────────────▼──────────┐  ┌───────▼───────────────────┐
│         Features         │  │        Design System      │
│ Library · NowPlaying ·   │  │ Typography · Color · Motion│
│ Queue · Settings         │  └───────────────────────────┘
└───────────────┬──────────┘
                │
┌───────────────▼─────────────────────────────────────────┐
│                      Domain                             │
│     Track · Album · Artist · Playlist · OutputMode      │
└───────────────┬─────────────────────┬───────────────────┘
                │                     │
┌───────────────▼──────────┐  ┌───────▼───────────────────┐
│     Library Service      │  │      Playback Service     │
│ Scan · Index · Search ·  │  │ Engine · Queue · Session  │
│ Artwork cache            │  │ NowPlaying info center    │
└───────────────┬──────────┘  └───────┬───────────────────┘
                │                     │
┌───────────────▼──────────┐  ┌───────▼───────────────────┐
│   SQLite catalogue       │  │      Audio Engine         │
│   + portable library     │  │ Protocol + CoreAudio impl │
│   + folder bookmarks     │  │ Decoders: PCM · DSD       │
└──────────────────────────┘  └───────────────────────────┘
```

---

## Audio engine (core differentiator)

### Protocol

```swift
protocol PlaybackEngine: AnyObject {
    var state: PlaybackState { get }
    func load(_ item: AudioItem) async throws
    func play()
    func pause()
    func seek(to seconds: TimeInterval)
    func setOutputDevice(_ id: AudioDeviceID?) // macOS
    func setExclusiveMode(_ enabled: Bool)     // macOS
}
```

### Pipeline (Mac, bit-perfect path)

```
File → Decoder → (optional DSD→DoP pack) → HAL Output Unit
                      │
                      └─ Exclusive mode + sample rate = source rate
```

Rules:
1. **Default = bit-perfect** for PCM when exclusive mode is on.
2. **Never silently resample** on the audiophile path; show a clear badge if conversion is active.
3. **DSD:** The output mode decides — Output DoP sends DoP (falls back to exclusive PCM, then Shared, if the DAC rejects the rate); Exclusive converts DSD to PCM on the exclusive HAL path; Shared converts to PCM. No separate DSD setting. DoP payload: oldest DSD bit in bit 15 (first byte high). The HAL IO buffer is ~50 ms and the mapped DSD file is prefetched ahead of the playhead — a missed cycle breaks the DoP marker run and the DAC mutes while it re-locks.
4. **DST:** MPEG-4 DST (Scarlet Book / DST-DFF) is lossless DSD compression. Harbor decodes each 1/75 s frame to raw DSD, caches an uncompressed DFF, then uses the normal DoP / PCM path. Do not play DST bytes as DSD.
5. **iOS:** Use `AVAudioEngine` / `AVAudioPlayerNode` + `AVAudioSession` category `.playback`; document that true exclusive HAL mode is a Mac strength.
6. **External DAC only:** Exclusive and DoP hog only USB / Thunderbolt / FireWire / PCI devices (`isExternalInterface`); everything else plays Shared so the volume keys keep working. While hogged, macOS moves the default output away, so decisions target the hogged device (`exclusiveTargetDevice`). The DAC stays hogged across tracks (rate switched only when needed); it is released on stop, on a Shared track, or on error. The output device is picked in Settings (stored by Core Audio UID; nil follows the system output) and applies to both HAL and the Shared graph (`kAudioOutputUnitProperty_CurrentDevice`); Exclusive needs an external interface, DoP additionally 176.4 kHz (`OutputStatus`). Changing device or mode reloads the current track at the same position. Output-device changes are observed live; Settings shows `effectiveOutputMode` (Shared without a DAC) while the stored Exclusive / DoP choice comes back on replug.
7. **Plugins:** The rack runs on the AVAudioEngine float graph. With Exclusive / DoP on an external DAC it is **Exclusive · FX**: before the graph is built, the DAC is hogged at the stream's rate (`claimOrReleaseDevice`) and the engine's output unit is pointed at the hogged device — no system mixer, no macOS resampling, not bit-perfect (the HAL converts float to the device format). DSD becomes PCM for the plugins. Otherwise Shared · FX. The app is sandboxed, so AUv2 components without `sandboxSafe` (UAD, Valhalla, bx, Kilohearts, …) are instantiated with `.loadOutOfProcess`; sandbox-safe AUv2 and AUv3 load normally. `AVAudioPlayerNode.play()` after a graph rewire is wrapped in the ObjC exception catcher.

### Decoders

| Format | Strategy |
|---|---|
| ALAC, AAC, MP3, WAV, AIFF | AVAudioFile / ExtAudioFile |
| FLAC | AVAudioFile (system) or libFLAC if gaps |
| DSF / DFF | Custom parser + DoP framer or PCM convert |
| SACD ISO | Scarlet Book stereo TOC → per-track catalogue rows; uncompressed DSD copied to a cached DFF |
| DST (SACD ISO / DFF) | Harbor MPEG-4 DST decoder (ISO/IEC 14496-3 Subpart 10) → cached uncompressed DFF → same DSD path |
| CUE | Later — not in the current build |

DST frames are 1/75 s of DSD64. Harbor does not play DST bytes as DSD. The common Scarlet Book layout (one segment, all channels) is decoded; a rare multi-segment frame fails with a clear error. There is no DST encoder and no Pine `.dst` container.

### Output modes (Mac)

| Mode | Behavior |
|---|---|
| Shared | System mixer (simple, compatible) |
| Exclusive | HAL exclusive; rate follows track |
| DoP | DSD packed in fake high-rate PCM for capable DACs |

---

## Library architecture

1. **Folder roots** stored as security-scoped bookmarks (this Mac + this app only).
2. **Scanner** walks trees, hashes path+mtime, extracts tags/artwork. Incremental; Rebuild is explicit.
3. **Catalogue** is SQLite+FTS5 (`catalogue.sqlite` in Application Support). UI never scans live on every open.
4. **Artwork** on-disk cache keyed by file hash.
5. **Search** via FTS5.

Identity of a track is `cataloguePath` (file path, plus virtual suffixes for SACD ISO / DFF chapters). Playlists and labels must key off that, never off scan UUIDs.

---

## Persistence (later)

Three kinds of data. Do not store them in the same place.

| Kind | Examples | Source of truth | Regenerable? |
|---|---|---|---|
| Access | Security-scoped folder bookmarks | App container / Keychain | No on a new Mac — user re-adds the folder |
| Cache | `catalogue.sqlite`, artwork, SACD / DST extract | Application Support + Caches | Yes — rescan / rebuild |
| Authored | Playlists, smart rules, labels | Portable Harbor library file | No |

**Rule:** files stay in the folders the user adds. Harbor’s memory of those files lives in Application Support. Harbor’s opinions (playlists, labels) live in a portable library file the user can back up — never inside every album folder, never only in UserDefaults.

### Do not put in the music folders

- The SQLite index. It is a speed cache. Two roots, a NAS, and Mac App Store `user-selected.read-only` all fight writing `catalogue.sqlite` next to FLACs.
- The only copy of playlists or labels. Album folders are not a database. A playlist can span roots.
- Tags written into the audio files by default. Mutating Vorbis/ID3 fights *Local. Bit-perfect. Calm.* Optional “write tags to files” can exist later, off.

### Do not leave authored data in UserDefaults

Playlists are JSON in UserDefaults today (`audioharbor.playlists`). Labels sit on SQLite rows and die on Rebuild. UserDefaults is size-capped, invisible, and dies with the container. Fine as a bootstrap, not as the library.

### Target layout

```
Application Support/AudioHarbor/
  catalogue.sqlite          ← cache, rebuildable
  artwork/
  bookmarks.json            ← this Mac only (security-scoped blobs)

Caches/AudioHarbor/
  SACD/                     ← disposable DFF extracts (uncompressed + DST decode)

~/Music/Audio Harbor/       ← user-owned; backup this
  library.json              ← playlists, smart rules, labels
  exports/                  ← optional M3U8 / XSPF
```

The library file location should be choosable (internal SSD, NAS, the music volume). Default `~/Music/Audio Harbor/` is enough for v1 of this work.

### Track identity in the library file

Relative paths from each folder root, not absolute paths and not UUIDs. `/Volumes/Music` vs `/Volumes/Music 1` must not empty playlists. Virtual catalogue paths (`path#sacd/N`, `path#dff/N`) stay as suffixes on the relative path.

### Optional export into the tree

Writing M3U8/XSPF *into* an added folder is a feature so foobar/VLC see the same list. It is a copy, not the source of truth. Needs write access to the target folder. The app has `user-selected.read-write` since the playlist export (save panel); folder bookmarks for the collection are still created read-only.

### New Mac / reinstall

1. Re-add the music folder (bookmark cannot travel).
2. Open the same `library.json` (or it lives on the music disk already).
3. Scan rebuilds `catalogue.sqlite`; playlists/labels rematch on relative paths.

### iCloud later

Sync the small library file, not the audio. See [`PRODUCT.md`](PRODUCT.md) (Library Pro: playlist sync, not files). No account in the product; iCloud is the user’s Apple ID, not Harbor’s.

**Not a date — an order.** iCloud is not in MVP and not in the first Mac App Store upload. Do this only after Exclusive/DoP and the sandbox are boring.

1. **Now / next persistence slice:** move playlists + labels out of UserDefaults / rebuild-fragile SQLite columns into `library.json` (app container or `~/Music/Audio Harbor/`). Relative paths. That is the whole feature for a while.
2. **Then:** user-picked location for that file (external disk / NAS). Export M3U optional.
3. **Then, Library Pro / Continuity:** iCloud Drive on the same small file so Mac and iPhone share playlists and labels. Catalogue SQLite stays local and rebuilds. Folder bookmarks stay per device — user re-adds the folder on the phone if needed.

Do not iCloud-sync `catalogue.sqlite` or bookmarks. Do not invent a Harbor account to sync it.

### MAS sandbox

`user-selected.read-write` (only so the save panel can write a playlist export) + app-scope bookmarks for the collection, created with `securityScopeAllowOnlyReadAccess`. The portable library file is user-selected or in the app’s own container until they pick a folder. Do not require write access to the music tree for Harbor to work.

---

## App navigation (UX architecture)

```
Root
 ├─ Library (sidebar Mac / tabs iOS)
 │   ├─ Albums
 │   ├─ Artists
 │   ├─ Folders
 │   └─ Playlists
 ├─ Now Playing (full + mini bar)
 └─ Settings
```

Hero rule for UI: **first viewport = brand + music**, not a control panel. Now Playing is the emotional center; Settings stay out of the way.

---

## Concurrency & state

- `@MainActor` view models for UI.
- Audio engine callbacks hop to MainActor for state publish.
- Scanning off main thread with progress stream.
- Prefer `AsyncStream` for scanner events and engine state.

---

## Project layout (repo)

```
Audio Harbor/
  App/                 # AudioHarborApp, RootView, DI
  DesignSystem/        # Colors, type, components
  Features/
    Library/
    NowPlaying/
    Settings/
  Domain/              # Pure models
  Services/
    Library/
    Playback/
  Audio/               # Engine + decoders
  Resources/
docs/
  PRODUCT.md
  ARCHITECTURE.md
project.yml            # XcodeGen
```

---

## Testing strategy

| Layer | Approach |
|---|---|
| Domain / queue | Unit tests |
| Decoder framing | Golden files (short FLAC/DSF fixtures) |
| Exclusive mode | Manual DAC checklist (documented) |
| UI | Snapshot later; smoke via previews now |

---

## Risks & mitigations

| Risk | Mitigation |
|---|---|
| DSD/DoP device quirks | Capability probe + explicit fallback UI |
| Sandbox bookmarks | Persist bookmarks; re-prompt clearly |
| Scope creep (Pine clone) | PRODUCT.md gate — Pro only after MVP calm |
| iOS “audiophile” expectations | Marketing honesty: Mac = DAC throne |
| Audio glitches on track change | Preload next buffer; gapless design early |

---

## Build & run

```bash
xcodegen generate
open Audio Harbor.xcodeproj
```

Select the **Audio Harbor** scheme → My Mac or iPhone Simulator.
