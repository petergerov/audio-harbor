# Audio Harbor — Technical Architecture

## Platforms & stack

| Layer | Choice |
|---|---|
| UI | SwiftUI (multiplatform) |
| Language | Swift 5.10+ / Swift 6 concurrency where safe |
| App shape | One shared target via XcodeGen → iOS + macOS |
| Persistence | SwiftData (library index) + FilePresenter/FSEvents (folder watch, Mac) |
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
│   SwiftData + Filesystem │  │      Audio Engine         │
│                          │  │ Protocol + CoreAudio impl │
│                          │  │ Decoders: PCM · DSD stub  │
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
3. **DSD:** Prefer DoP to DAC; if unsupported → high-quality PCM conversion with UI disclosure.
4. **iOS:** Use `AVAudioEngine` / `AVAudioPlayerNode` + `AVAudioSession` category `.playback`; document that true exclusive HAL mode is a Mac strength.

### Decoders

| Format | Strategy |
|---|---|
| ALAC, AAC, MP3, WAV, AIFF | AVAudioFile / ExtAudioFile |
| FLAC | AVAudioFile (system) or libFLAC if gaps |
| DSF / DFF | Custom parser + DoP framer or PCM convert |
| CUE / SACD ISO | Pro only |

### Output modes (Mac)

| Mode | Behavior |
|---|---|
| Shared | System mixer (simple, compatible) |
| Exclusive | HAL exclusive; rate follows track |
| DoP | DSD packed in fake high-rate PCM for capable DACs |

---

## Library architecture

1. **Folder roots** stored in settings (security-scoped bookmarks on both platforms).
2. **Scanner** walks trees, hashes path+mtime, extracts tags/artwork.
3. **SwiftData** stores `TrackEntity`, `AlbumEntity`, relations; UI never scans live on every open.
4. **Artwork** on-disk cache keyed by album id / file hash.
5. **Search** via SwiftData predicates first; Spotlight later if needed.

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
