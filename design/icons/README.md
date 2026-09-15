# App-Icon

Gewählt: **Entwurf 6 — Typenschild**. Die Übersicht aller sechs Entwürfe liegt in `uebersicht.html`.

## Quellen

| Datei | Zweck |
| --- | --- |
| `icon-6-typenschild.svg` | Vollversion mit Wortmarke — ab 64 px |
| `icon-6-typenschild-klein.svg` | Monogramm „AH“ — bis 32 px, dort verschmelzen zwei Zeilen Versalien |
| `icon-6-typenschild-ios.svg` | randlos quadratisch, ohne Squircle — iOS maskiert selbst |

Die Entwürfe 1 bis 5 bleiben als SVG liegen; Entwurf 1 hat noch seine drei Master
(`icon-1-plattenteller*.svg`), falls die Richtung doch wieder gewechselt wird.

Farben stammen aus `HarborTheme.swift`, nicht aus einer eigenen Palette.

## Neu bauen

```bash
design/icons/tools/build-appicon.sh
```

Rendert `AppIcon.appiconset` neu. `render.swift` zeichnet das SVG über AppKit
vektor-scharf in jeder Zielgröße:

- **mac** — auf Apples Raster eingerückt (824 von 1024), mit Schlagschatten, transparenter Rand
- **bleed** — deckend ohne Alphakanal, den lehnt der App Store bei iOS-Icons ab

Zwei Fallstricke, die hier schon zugeschlagen haben: `qlmanage` taugt nicht als
Renderer, es legt die Grafik auf einen deckenden Grund. Und AppKit versteht
`clip-path="inset(…)"` nicht — Zuschnitte brauchen ein echtes `<clipPath>`,
sonst laufen sie im Icon aus, während der Browser sie korrekt zeigt.
