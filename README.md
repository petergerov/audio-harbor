# Audio Harbor

Local audiophile player for macOS and iOS. Add music folders, browse a quiet catalogue, and play high-res files as they are — bit-perfect Exclusive and DoP on Mac, Shared as the stable default.

Optional AUv3 inserts sit on the Deck rack when you want processing. No streaming, no accounts, no feature maze: open a folder, hear the file.

## Docs

- [Homepage (marketing)](docs/index.html)
- [Marketing concept](docs/MARKETING.md)
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
- Real metadata + artwork via AVFoundation / DSD probe
- Mac exclusive mode: hog + sample-rate match + HAL 24-bit path
- DSF / DFF → DoP (or DSD→PCM fallback)
- SACD ISO stereo tracks, including MPEG-4 DST → cached DFF → same DSD path
- Shared AVAudioEngine path as default/stable playback

## Formats

FLAC · ALAC · WAV · AIFF · AAC · MP3 · DSF · DFF · SACD ISO (stereo, including DST)
