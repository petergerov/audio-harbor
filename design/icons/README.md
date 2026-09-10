# App-Icon

Gewählt: **Entwurf 1 — Plattenteller**. Die Übersicht aller sechs Entwürfe liegt in `uebersicht.html`.

## Quellen

| Datei | Zweck |
| --- | --- |
| `icon-1-plattenteller.svg` | Vollversion mit Gravur „AUDIO HARBOR“ — ab 128 px |
| `icon-1-plattenteller-klein.svg` | ohne Gravur, Motiv 5 % größer — bis 64 px |
| `icon-1-plattenteller-ios.svg` | randlos quadratisch, ohne Squircle — iOS maskiert selbst |

Farben stammen aus `HarborTheme.swift`, nicht aus einer eigenen Palette.

## Neu bauen

```bash
design/icons/tools/build-appicon.sh
```

Rendert `AppIcon.appiconset` neu. `render.swift` zeichnet das SVG über AppKit
vektor-scharf in jeder Zielgröße:

- **mac** — auf Apples Raster eingerückt (824 von 1024), mit Schlagschatten, transparenter Rand
- **bleed** — deckend ohne Alphakanal, den lehnt der App Store bei iOS-Icons ab

`qlmanage` taugt dafür nicht: es legt die Grafik auf einen deckenden Grund.
