# Audio Harbor

Local audiophile player for macOS and iOS. Add music folders, browse a quiet catalogue, and play high-res files as they are — bit-perfect Exclusive and DoP on Mac, Shared as the stable default.

Optional AU / AUv3 inserts sit on the Deck rack when you want processing. No streaming, no accounts, no feature maze: open a folder, hear the file.

## Docs

- [Homepage (marketing)](docs/index.html)
- [Marketing concept](marketing/MARKETING.md)
- [Product scope (MVP vs Pro)](docs/PRODUCT.md)
- [Technical architecture](docs/ARCHITECTURE.md)
- [Brand](docs/brand.md)

## Generate & run

```bash
xcodegen generate
open AudioHarbor.xcodeproj
```

Select the **AudioHarbor** scheme → **My Mac** or an iPhone simulator → Run.

## What’s in the current build

- Security-scoped folder bookmarks (persist across launches)
- Catalogue: directories, albums, artists; playlists and labels
- Click plays and stays in the list; ⌘-click, *Play and Show Deck*, the mini player or ⌘3 open the Deck
- Right-click a directory, album, artist or the Deck queue → Add to Playlist / Labels
- Shortcuts: Space, ⌘← / ⌘→, ⌘1 Catalogue, ⌘2 Playlists, ⌘3 Deck, ⌘, Settings, ⌘O, ⇧⌘R
- M3U / M3U8 playlist import and export
- Real metadata + artwork via AVFoundation (incl. FLAC Vorbis comments) / DSD probe; folder images (`cover`, `folder`, `front`, …) when a file has none
- Albums grouped by album artist; untagged compilations in one folder stay one album
- iPhone and iPad remote: Bonjour + pairing code; browse, queue, transport, DAC volume; long-press a song to add it to playlists and labels or take it out; search under Dirs / Albums / Artists / Lists like on the Mac; playing stays in the list; the iPad shows the same layout as the iPhone
- Mac exclusive mode: hog + sample-rate match + HAL 24-bit path, external DACs only (USB / Thunderbolt / FireWire / PCI); Exclusive and DoP grey out without one and the choice returns when the DAC is plugged in
- DSF / DFF → DoP in Output DoP; DSD→PCM in Shared and Exclusive
- SACD ISO stereo tracks, including MPEG-4 DST → cached DFF → same DSD path
- Shared AVAudioEngine path as default/stable playback
- AU / AUv3 rack on Shared; non-sandbox-safe AUv2 load out of process

## Formats

FLAC · ALAC · WAV · AIFF · AAC · MP3 · DSF · DFF · SACD ISO (stereo, including DST)

## Docs

- [FAQ](https://petergerov.github.io/audio-harbor/faq.html) — output modes, DAC, DSD, plugins, playlists
- [Settings explained (German)](docs/settings.md)
- [Architecture](docs/ARCHITECTURE.md) · [Product](docs/PRODUCT.md)
