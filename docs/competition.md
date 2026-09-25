# Audio Harbor — Wettbewerb & Preis

Stand: **25. September 2026**. Preise aus dem US Mac App Store bzw. den Hersteller-Seiten, sofern nicht in € angegeben. Vor jeder Preisänderung neu prüfen.

---

## Preise der Konkurrenz

| App | Preis | Modell | Relevanz |
|---|---|---|---|
| **Pine Player Pro** | **29,99 $** | Paid App, kein Trial | DoP, SACD ISO, Exclusive — direktes Vorbild / Hauptgegner |
| Pine Player | Free | — | Lite-Version |
| **Colibri** | **19,99 $** | Paid App | Bit-perfect, Exclusive / Hog; DSD nicht geprüft |
| **Fidelia** | Free + 14 Tage Trial → **99,99 $** (+ 49,99 $ Network & Server) | Non-Consumable Unlock | Exclusive, DoP — gleiches Modell wie wir, viel teurer |
| Vox | Free, Premium ab 4,99 $/Monat | Abo | Mainstream |
| Swinsian | 34,95 $ | Einmalig, außerhalb MAS | Library-Manager |
| BitMuse | 99,95 $ | Einmalig | Exclusive, DoP |
| **Audirvāna Origin** | **149,99 €** | Einmalig | Voller Funktionsumfang |
| Audirvāna Studio | 7,99 €/Monat · 79,99 €/Jahr (seit 6. Jan. 2026) | Abo | Mit Streaming |
| **Roon** | 14,99 $/Monat · 829,99 $ lifetime | Abo / Lifetime | Multiroom, Server |

Bewertungszahlen waren auf den US-Store-Seiten bei keiner der Apps sichtbar („nicht genug Bewertungen“) — die Nische ist klein.

## Einordnung

- Schlanke Player liegen bei **20–30 $**, die großen Namen bei **100–150 $** oder im Abo.
- Pine Player Pro kostet 29,99 $ ohne Trial. Audio Harbor bietet DoP, SACD ISO inkl. DST und das AU-Rack, ruhigere UI und 7 Tage Probe — kein Grund, bei einem Drittel davon zu liegen.
- Fidelia beweist: Free + Trial + einmaliger Unlock funktioniert in dieser Zielgruppe, sogar bei 99,99 $.
- Einmalig, ohne Abo, ohne Account ist das Argument gegen Audirvāna Studio und Roon.
- Die Zielgruppe (externer DAC, DSD, SACD ISO) ist wenig preissensibel; ein niedriger Preis wirkt eher wie „Spielzeug“.

## Preisempfehlung

| Phase | Preis |
|---|---|
| Launch (2–4 Wochen) | **14,99 €** — als Launch-Preis kommuniziert, für erste Reviews |
| Regulär | **19,99 €** — auf Colibri-Niveau, klar unter Pine Player Pro |
| Später mit iPhone / iPad (ein Kauf, alle Geräte) | **24,99–29,99 €** |

Modell bleibt: Free App, Trial, Non-Consumable `com.gerov.audioharbor.unlock`, kein Abo. Trial von 7 auf **14 Tage** erwägen (Fidelia-Niveau; Audiophile testen mit mehreren DACs).

Aktuell steht in [`APP_STORE_SUBMISSION.md`](../APP_STORE_SUBMISSION.md) noch **9,90 €** — bei Umstellung Promotional Text, Beschreibung, IAP-Abschnitt und den Review-Screenshot anpassen. Die App selbst zeigt `displayPrice` aus StoreKit.

## EQ, Effekte und DSD

> Aus allgemeinem Wissen zusammengestellt, **nicht gegen die aktuellen Handbücher geprüft**. Vor Verwendung in Marketing oder Vergleichen je App verifizieren.

### Warum DSP immer PCM heißt

DSD ist ein 1-Bit-Strom mit 2,8 MHz und mehr; die Information steckt in der Pulsdichte, nicht in Samplewerten. EQ, Faltung, selbst eine Lautstärkeänderung brauchen echte Samplewerte. Deshalb arbeiten alle Player gleich:

```
PCM-Datei ────────────────┐
                          ├─► Float-PCM (32/64 Bit) ─► EQ / FX / Lautstärke ─► Dither ─► 24/32-Bit-PCM ─► DAC
DSD-Datei ─► DSD→PCM ─────┘                                                          └─► (optional) PCM→DSD-Modulator ─► DoP/nativ DSD ─► DAC
```

Sobald DSP aktiv ist, ist die Wiedergabe **nicht mehr bit-perfect** — auch im Exclusive-Modus. Der DAC bekommt sauberes PCM mit fester Rate, aber nicht mehr die Originalbits.

### Wie es die Konkurrenz macht

| App | EQ / Effekte | DSD bei aktivem DSP | Ausgabe mit DSP |
|---|---|---|---|
| **Pine Player Pro** | Eingebauter 12-Band-EQ, EQ pro Track | → PCM | EQ nur im DAC-Modus „Equalizer“; „Priority“ (bit-perfect) schaltet den EQ ab |
| **Audirvāna** | AU-Plugins, Upsampling (SoX / r8brain), eigene kostenpflichtige DSP-Suite | → PCM | Bleibt exclusive (Hog / Integer Mode) mit DSP |
| **Roon** | Parametrischer EQ, Faltung, Crossfeed, Headroom, Sample-Rate-Konvertierung | → PCM, optional zurück zu DSD | PCM oder mit eigenem Modulator neu erzeugtes DSD |
| **Fidelia** | AU-Plugins, Upsampling | → PCM | Bleibt exclusive (Hog) mit DSP |
| **HQPlayer** (Referenz) | Filter, Faltung, EQ | → PCM | Spezialität: PCM→DSD-Modulation, z. B. DSD256 aus jeder Quelle |
| **Vox, Swinsian** | Einfacher EQ | Vox → PCM; Swinsian kaum DSD | Über den System-Mixer, nicht bit-perfect |
| **Colibri** | Wenig bis nichts — Verkaufsargument ist bit-perfect | — | — |

### Was der DAC sieht

- **PCM + DSP, exclusive:** App hält den DAC, setzt die Rate (Datei- oder Upsampling-Rate). Der DAC bekommt verarbeitetes 24/32-Bit-PCM; kein Mixer, kein macOS-Resampling — aber veränderte Samples.
- **PCM + DSP, shared:** Gleiche Verarbeitung, danach zusätzlich macOS-Mixer und ggf. Resampler. Das ist Audio Harbors „Shared · FX“.
- **DSD neu moduliert (Roon, HQPlayer):** Der DAC bekommt wieder DoP / natives DSD und zeigt „DSD“ an — aber ein neu modulierter Strom, nicht die Originalbits. Die Qualität hängt am Modulator; gute Modulatoren brauchen viel CPU.
- **Lautstärke:** Digitale Lautstärke ist ebenfalls DSP. Seriöse Player geben Headroom und Dither — oder lassen die Lautstärke beim DAC, wie Audio Harbor in Exclusive.

### Konsequenz für Audio Harbor

- Audio Harbor folgt der Branchenregel (Rack aktiv → PCM, nicht bit-perfect).
- **Umgesetzt: „Exclusive · FX“** — mit Plugins und Exclusive / DoP auf einem externen DAC hält Audio Harbor den DAC (Hog) auf der Rate der Datei, der Plugin-Graph spielt direkt hinein: kein System-Mixer, kein macOS-Resampling. Gleichstand mit Audirvāna / Fidelia. Offen: eigener Dither auf 24 Bit (heute wandelt der HAL Float → Integer).
- **Nicht verfolgen: DSD-Remodulation nach DSP** (wie Roon / HQPlayer) — großes Projekt, der Wert liegt im Modulator, und es passt nicht zur einfachen Produktgeschichte.

## Quellen

- [Pine Player Pro — App Store](https://apps.apple.com/us/app/pine-player-pro/id6474128342?mt=12)
- [Pine Player — App Store](https://apps.apple.com/us/app/pine-player/id1112075769?mt=12)
- [Fidelia — App Store](https://apps.apple.com/us/app/fidelia-audiophile-player/id416135376?mt=12)
- [Colibri — App Store](https://apps.apple.com/us/app/colibri/id1178295426?mt=12)
- [Audirvāna Preise](https://audirvana.com/price/)
- [Roon Pricing](https://roon.app/en/pricing)
- [BitMuse: Mac-Player-Vergleich 2026](https://bitmuse.app/best-music-player-mac)
- [FileMinutes: Best Audio Players for macOS](https://www.fileminutes.com/blog/best-audio-players-for-macos-2025/)
