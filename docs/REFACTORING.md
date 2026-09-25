# Readability refactoring plan

Goal: make the code easier to read and change without changing what the app does. Every step
builds on its own, keeps behaviour identical, and lands as its own commit.

Rules from `.claude/CLAUDE.md` that drive this: passive views, `@Observable` + `@MainActor`
view models, no heavy work in `body`, small subviews, `.task` over `.onAppear`.

Status: ☐ todo · ◐ in progress · ☑ done

---

## 1. Split `LibraryService.swift` (1,747 → 776 lines) ☑

One file held the observable catalogue, folder navigation, labels, the SQLite store, the search
index, the indexer and an `Array` helper.

| Step | Change |
|---|---|
| 1a ☑ | Move non-service types into their own files: `CatalogueRecords.swift` (`IndexedTrackRecord`, `FileFingerprint`, `StoredFingerprint`), `CatalogueIndexStore.swift`, `CatalogueSearchIndex.swift`, `CatalogueIndexer.swift` (+ the private `Array.chunked`). |
| 1b ☑ | `TrackLabelStore`: labels keyed by catalogue path, UserDefaults load/save and add/remove/set rules. `LibraryService` keeps its public label API and only re-applies labels to tracks. Prepares the move of labels to `library.json` (see `ARCHITECTURE.md`). |
| 1c ☑ | `FolderNavigation` value type: selected root + path components, with `open`, `enter`, `goUp`, `jump(toDepth:)`, `reset`. Views use `library.folderNavigation.*`. |
| 1d ☑ | `FolderDiskScanner`: disk-only listing and "contains audio" probe, off the service. `DemoLibrary.tracks` for the demo catalogue. |
| 1e ☑ | Remove dead code (`indexedDirectories(under:)`, `directoryContainsSupportedAudio`) and use one path-normalising helper instead of three inline copies. |

Found while doing this (not fixed, behaviour kept): `revealInFolders` matches a root by plain
string prefix, so `/Music` also claims `/Music2/...`.

## 2. Shared play entry point ☐

`playback.play(track:in:sourceName:sourceKind:)` + `selectedTab = .nowPlaying` appears 10 times,
with `sourceKind` as a raw string in 7. Add `enum QueueSource` and
`AppModel.play(_:startingAt:from:)`.

## 3. Keep expensive work out of `body` ☐

- `LibraryService.folderListing` scans all tracks (and maybe the disk) and is read twice per
  render. Make it stored state refreshed when the folder location or catalogue changes.
- `trackForPlayback(at:)` runs per row in `body`.
- `NowPlayingView.artworkImage(_:)` decodes an image on every render — cache per track.

## 4. View models for Catalogue and Playlists ☐

- `LibraryViewModel`: search debounce, expanded album/artist, new-playlist alert, play actions.
- `PlaylistsViewModel`: M3U import + summary, untitled-name logic, `tracks(for:)`, titles.

## 5. De-duplicate catalogue rows ☐

- One configured track row instead of four identical closure sets around `TrackRow`.
- `ExpandableTrackSection` shared by the album and artist lists.
- One "Add to Playlist" menu.

## 6. Split `CoreAudioPlaybackEngine.swift` (1,053 lines) ☐

- Break `play()` into exclusive start / shared fallback / shared start.
- Move `StereoMeterProbe` and VU maths to `Meters.swift`.
- `PathLabel` enum for the "Exclusive · DoP" family of strings; one error-logging helper.

## 7. Small cleanups ☐

- One `DefaultsKey` namespace for the 16 `audioharbor.*` keys.
- One m:ss formatter (three copies today).
- `.harborListRow()` modifier (11 copies); `EmptyPanel(title:message:)`.
- De-duplicate the macOS / iPad-regular split layout in `PlaylistsView`.
- `LibraryView` `.onAppear` → `.task`.
- Drop legacy migrations (`audioharbor.dsdStrategy`, `"cassette"` deck style) once safe.

## Out of scope

`HALAudioPlayer`, `PCMRing`, `DSDDecoder`, `SACDISO`: real-time audio code where
`@unchecked Sendable` and dispatch queues are deliberate. Not worth the glitch risk.
