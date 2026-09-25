# App-Icon

Aktuell: **Kopfhörer über Wellen, Gold auf Schwarz** (PNG-Master, September 2026).

## Quellen

| Datei | Zweck |
| --- | --- |
| `icon.png` | Kachel mit Wortmarke „AUDIO HARBOR“ — App-Icon ab 64 px, iOS 1024 |
| `icon_no_text.png` | nur das Symbol — App-Icon bei 16 / 32 px (dort ist die Schrift unlesbar), Homepage-Logo in Nav und Footer, Link-Vorschau |
| `Icon_favorite.png` | Favicon (32 / 64 px) und Apple-Touch-Icon (180 px) der Homepage — weiße Ecken, `render-favicon.swift` stellt sie frei |

Beide Master bringen ihre eigene, goldumrandete Kachel auf dunklem Grund mit.
Der Renderer findet den Goldrahmen über die Helligkeit, liest den Eckradius an der
45°-Diagonale ab und verwirft alles außerhalb des Rahmens.

Die früheren SVG-Entwürfe (1 bis 6, zuletzt „Typenschild“) bleiben liegen;
`render.swift` rendert sie weiterhin, falls die Richtung zurückwechselt.
Die Übersicht dazu liegt in `uebersicht.html`.

## Neu bauen

```bash
design/icons/tools/build-appicon.sh
```

Rendert `AppIcon.appiconset` sowie `docs/images/web/icon-128.png`, `favicon-32.png`,
`favicon-64.png`, `icon-180.png` und `docs/AppIcon.png` (Link-Vorschau) neu. `render-png.swift` kennt drei Modi:

- **mac** — Kachel auf ihre eigene Rundung zugeschnitten, auf Apples Raster (824 von 1024), mit Schlagschatten, transparenter Rand
- **web** — Kachel formatfüllend, transparente Ecken (Homepage, Favicon)
- **bleed** — deckend ohne Alphakanal, den lehnt der App Store bei iOS-Icons ab; iOS maskiert selbst

Nach einem neuen Icon zeigt das Dock manchmal noch das alte — macOS cached Icons.
Clean Build (⇧⌘K) und die App neu starten hilft.
