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

## 2. Shared play entry point ☑

`playback.play(track:in:sourceName:sourceKind:)` + `selectedTab = .nowPlaying` appeared 9 times,
with `sourceKind` as a raw string. Now `AppModel.play(_:startingAt:from:)` takes a
`QueueSource` (`.album`, `.artist`, `.folder`, `.playlist`, `.label`); `PlaybackService` stores
it, and the Deck rail matches `.playlist` instead of comparing `"Playlist"`.

## 3. Keep expensive work out of `body` ☑

- `LibraryService.folderListing` is stored state, rebuilt by `refreshQueryResults()` whenever
  the search query, folder location or catalogue changes (was: rescanned on every read, twice
  per render). Trade-off: a folder listed from disk mid-scan refreshes when the scan lands,
  not on every redraw.
- `FolderBrowseEntry.Kind.audioFile` carries its `Track`, resolved once when the listing is
  built; rows no longer call `trackForPlayback` (now private).
- The Deck decodes cover art once per track in `.task(id:)`; it used to decode on every
  playback tick. `Image(artworkData:)` is shared with `HarborArtwork`.

## 4. View models for Catalogue and Playlists ☑

Each screen owns its view model as `@State`, created in `init(appModel:)`, so screen state
still resets when the macOS sidebar switches screens (as before).

- `LibraryViewModel`: debounced `searchDraft`, expanded album / artist, the pending
  "New Playlist" track, adding directories, subtitle, and every play action
  (`playAlbum`, `playArtist`, `playDirectory`, `playRoot`, `playFolder(containing:)`).
- `PlaylistsViewModel`: sidebar `scope` (persisted, drops an out-of-scope selection) and
  `selection`, `tracks(for:)` / titles, create / rename / delete, track removal, M3U import
  with its summary, and M3U8 writing. The save panel stays in the view.

## 5. De-duplicate catalogue rows ☑

- `TrackRow(track:onPlay:)` in its own file. Its right-click menu comes from
  `.trackContextMenu(for:includesLabels:leading:)`, which owns Add to Playlist, Labels and
  the "New Playlist…" / "New Label…" prompts. Folder search hits use the same modifier
  with their own leading items (and no Labels menu, as before), which removed the
  screen-level "New Playlist" alert and `pendingPlaylistTrack`.
- `ExpandableTrackGroup` renders the album and artist lists (header, play button, expanded
  tracks); the two list views only supply titles, thumbnail and actions.

## 6. Tidy `CoreAudioPlaybackEngine.swift` (1,053 → 978 lines) ☑

Behaviour-preserving only: this is the audio path.

- `StereoMeterProbe` and the needle maths (`VUNeedle`) live in `StereoMeter.swift`.
- `play()` reads as: exclusive → `startExclusivePlayback()` → on failure
  `fallBackToShared(after:)`; else shared. `exclusivePathLabel(for:)` names the caption.
- One `logFailure(_:_:)` for the five "domain code description" error logs.
- `pause()` shares its tail; `showFXPathLabelIfActive()` and `pathLabelDescribesLoad`
  replace four copies of the FX-caption rule and the substring test.
- `resetSharedGraphIfNeeded()` → `rebuildSharedGraph()` (it always rebuilt), also used by
  `handleEffectChainChanged()` instead of a copy. `MARK` sections throughout.
- Not done: a typed `PathLabel`. The engine decides things by substring of the caption
  (`"DSD"`, `"fallback"`, `"external"`), so typing it is a logic change. Worth doing with
  a DAC on the desk to test every path.

## 7. Small cleanups ☐

- One `DefaultsKey` namespace for the 16 `audioharbor.*` keys.
- One m:ss formatter (three copies today).
- `.harborListRow()` modifier (11 copies); `EmptyPanel(title:message:)`.
- De-duplicate the macOS / iPad-regular split layout in `PlaylistsView`.
- ~~`LibraryView` `.onAppear` → `.task`~~ — gone with step 4.
- Drop legacy migrations (`audioharbor.dsdStrategy`, `"cassette"` deck style) once safe.

## Out of scope

`HALAudioPlayer`, `PCMRing`, `DSDDecoder`, `SACDISO`: real-time audio code where
`@unchecked Sendable` and dispatch queues are deliberate. Not worth the glitch risk.
