# Audio Harbor

Local audiophile player for macOS and iOS — bit-perfect where it matters, calm UI.

**Subtitle:** Local audiophile player

## Docs

- [Product scope (MVP vs Pro)](docs/PRODUCT.md)
- [Technical architecture](docs/ARCHITECTURE.md)
- [Brand](docs/brand.md)

## Generate & run

```bash
xcodegen generate
open AudioHarbor.xcodeproj
```

Select the **AudioHarbor** scheme → **My Mac** or an iPhone simulator → Run.

## What’s in v0.2

- Security-scoped folder bookmarks (persist across launches)
- Real metadata + artwork via AVFoundation / DSD probe
- Mac exclusive mode: hog + sample-rate match + HAL 24-bit path
- DSF → DoP (or DSD→PCM fallback); DFF probe (playback next)
- Shared AVAudioEngine path as default/stable playback

## MVP formats

FLAC · ALAC · WAV · AIFF · AAC · MP3 · DSF (DoP/PCM) · DFF (probe)
