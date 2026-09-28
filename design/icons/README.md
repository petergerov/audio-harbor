# App-Icon

Aktuell: **Kopfhörer über Wellen, Gold auf flacher schwarzer Kachel** (PNG-Master, September 2026).

## Quellen

| Datei | Zweck |
| --- | --- |
| `Icon_favorite.png` | Kachel mit Wortmarke „AUDIO HARBOR“ auf weißem Grund — App-Icon ab 64 px und iOS 1024; außerdem Favicon (32 / 64 px) und Apple-Touch-Icon (180 px) der Homepage |
| `icon_no_text_2d.png` | dieselbe Kachel ohne Schrift, auf schwarzem Grund — App-Icon bei 16 / 32 px (dort ist die Schrift unlesbar); Marke in Nav und Footer der Homepage (`mark-40/80/120`, daneben „AUDIO HARBOR“ als Text) |
| `icon_no_text.png` | älteres Symbol mit Goldrahmen — Link-Vorschau der Homepage |
| `logo_homepage.png` | Symbol mit Wortmarke auf dunklem Grund — Logo oben in der Seitenleiste der App (`BrandLogo`, 40 pt hoch); `render-logo.swift` entfernt den Grund und schneidet auf das Logo zu |
| `logo.png` | ältere Fassung mit engerem Abstand zwischen Symbol und Wortmarke — nicht mehr verwendet |

`render-png.swift` findet die Kachel auf zwei Arten: Haben alle vier Ecken dieselbe Farbe
(weiß oder schwarz), ist die Kachel alles, was sich davon abhebt; sonst sucht er den
Goldrahmen über die Helligkeit. Den Eckradius liest er an der 45°-Diagonale ab und verwirft
alles außerhalb der Kachel. `render-favicon.swift` stellt die weißen Ecken von
`Icon_favorite.png` für die Homepage frei.

Die früheren SVG-Entwürfe (1 bis 6, zuletzt „Typenschild“) bleiben liegen;
`render.swift` rendert sie weiterhin, falls die Richtung zurückwechselt.
Die Übersicht dazu liegt in `uebersicht.html`.

## Neu bauen

```bash
design/icons/tools/build-appicon.sh
```

Rendert `AppIcon.appiconset`, `BrandLogo.imageset`, `docs/images/web/mark-40/80/120` (PNG + WebP) sowie `favicon-32.png`,
`favicon-64.png`, `icon-180.png` und `docs/AppIcon.png` (Link-Vorschau) neu. `render-png.swift` kennt drei Modi:

- **mac** — Kachel auf ihre eigene Rundung zugeschnitten, auf Apples Raster (824 von 1024), mit Schlagschatten, transparenter Rand
- **web** — Kachel formatfüllend, transparente Ecken (Homepage, Favicon)
- **bleed** — deckend ohne Alphakanal, den lehnt der App Store bei iOS-Icons ab; iOS maskiert selbst

Nach einem neuen Icon zeigt das Dock manchmal noch das alte — macOS cached Icons.
Clean Build (⇧⌘K) und die App neu starten hilft.
