# Einstellungen – kurz erklärt

## Output: Wie kommt der Ton aus der App?

**Wenn du unsicher bist: Shared.**

| Modus | Wofür | Was passiert |
|---|---|---|
| **Shared** | Alltag. Lautsprecher, Kopfhörer, Bluetooth, AirPlay | Die App spielt wie jede andere App. Andere Töne laufen weiter. macOS mischt und passt die Abtastrate an. |
| **Exclusive** | USB-DAC, hochauflösende Dateien | Die App übernimmt den DAC allein und stellt ihn auf die Abtastrate der Datei. Die Musik kommt **bit-perfect** an, also unverändert. Andere Apps sind stumm. DSD-Dateien werden in PCM umgerechnet. |
| **DoP** | USB-DAC, **der DSD kann** | Wie Exclusive. Zusätzlich gehen DSD-Dateien (DSF, DFF, SACD ISO) als echtes DSD an den DAC. |

Exclusive und DoP gibt es nur auf dem Mac und nur mit einem externen USB-DAC.

## DSD: Was ist DoP?

DSD ist ein anderes Audioformat als das übliche PCM. Über USB lässt sich aber nur PCM übertragen.
**DoP** („DSD over PCM“) verpackt die DSD-Daten deshalb in PCM-Pakete mit einer Markierung.
Der DAC erkennt die Markierung, packt die Daten aus und spielt echtes DSD.

- **Dein DAC kann DSD** → Output **DoP** wählen.
- **Dein DAC kann kein DSD** → Output **Exclusive** wählen. DSD wird dann in PCM umgerechnet.
  Wichtig: Ein DAC ohne DSD macht aus DoP lautes Rauschen.
- Kann der DAC die DoP-Rate nicht annehmen, wechselt die App automatisch zu PCM.
- DoP geht nur an externe Geräte (USB, Thunderbolt, FireWire, PCI). Eingebaute Lautsprecher,
  virtuelle Geräte (z. B. VB-Cable, BlackHole), Bluetooth und AirPlay bekommen immer PCM.

Eine eigene DSD-Einstellung gibt es nicht mehr. Der Output-Modus entscheidet.

## Welche DSD-Wiedergabe bei welchem Output?

| Output | DSD-Dateien | Normale Dateien (FLAC, WAV …) |
|---|---|---|
| Shared | umgerechnet in PCM | über macOS |
| Exclusive | umgerechnet in PCM, exklusiv | bit-perfect |
| DoP | echtes DSD per DoP | bit-perfect |

Auf dem Deck steht immer, welcher Weg aktiv ist, z. B. „Exclusive · Bit-perfect“, „DoP“ oder „Exclusive · DSD→PCM“.

## Plugins (Rack)

- Plugins funktionieren nur auf dem Shared-Weg. Sobald ein Plugin im Rack ist, schaltet die App automatisch auf **Shared · FX**.
- Ist das Rack leer, gelten Exclusive und DoP wieder.
- Unterstützt werden AUv3 und klassische AU-Plugins (Stereo).
  Klassische Plugins, die nicht „sandbox-safe“ sind (z. B. UAD, Valhalla), laufen in einem eigenen Prozess von macOS.

## Directories

Hier fügst du die Ordner mit deiner Musik hinzu. Die App liest nur. Sie verschiebt und verändert keine Dateien.

## License

7 Tage kostenlos ab der ersten Installation, danach einmalig freischalten.
Nach einer Neuinstallation oder auf einem neuen Mac stellst du den Kauf mit „Restore Purchases“ wieder her.
