# Einstellungen – kurz erklärt

## Output: Wie kommt der Ton aus der App?

**Wenn du unsicher bist: Shared.**

### Device: Wohin spielt die App?

- **System Output** (Standard): Die App spielt dorthin, wo macOS gerade spielt.
- **Ein bestimmtes Gerät**, z. B. dein DAC: Die Musik geht immer dorthin, egal was macOS eingestellt hat.
  So bleiben Systemtöne, Browser oder Zoom auf den Mac-Lautsprechern, und nur die Musik läuft über den DAC.
- Neben jedem Gerät steht, was es kann: **Exclusive · DoP**, **Exclusive** oder **Shared only**.
- Wechselst du das Gerät während ein Song läuft, spielt er an derselben Stelle auf dem neuen Gerät weiter.
- Ist dein gewähltes Gerät nicht angesteckt, spielt die App über System Output. Steckst du es wieder an,
  wird es ab dem nächsten Song wieder benutzt.
- Exclusive und DoP sind nur wählbar, wenn das Gerät sie kann: Exclusive braucht einen externen DAC,
  DoP zusätzlich 176,4 kHz. Auch der Modus lässt sich mitten im Song wechseln.

| Modus | Wofür | Was passiert |
|---|---|---|
| **Shared** | Alltag. Lautsprecher, Kopfhörer, Bluetooth, AirPlay | Die App spielt wie jede andere App. Andere Töne laufen weiter. macOS mischt und passt die Abtastrate an. |
| **Exclusive** | USB-DAC, hochauflösende Dateien | Die App übernimmt den DAC allein und stellt ihn auf die Abtastrate der Datei. Die Musik kommt **bit-perfect** an, also unverändert. Andere Apps sind stumm. DSD-Dateien werden in PCM umgerechnet. |
| **DoP** | USB-DAC, **der DSD kann** | Wie Exclusive. Zusätzlich gehen DSD-Dateien (DSF, DFF, SACD ISO) als echtes DSD an den DAC. |

Exclusive und DoP gibt es nur auf dem Mac und nur mit einem externen DAC (USB, Thunderbolt, FireWire, PCI).
An eingebauten Lautsprechern und Kopfhörern, virtuellen Geräten (z. B. VB-Cable), Bluetooth und AirPlay
spielt die App automatisch über Shared. Auf dem Deck steht dann „Shared · No external DAC“.
Ohne externen DAC sind Exclusive und DoP in den Settings ausgegraut, und **Shared** ist ausgewählt.
Steckst du den DAC wieder an, wählt die App automatisch wieder deine vorherige DAC-Einstellung (Exclusive oder DoP).

**Lautstärke:** In Exclusive und DoP regelst du die Lautstärke am DAC oder Verstärker.
Die Lautstärketasten des Mac wirken dann nicht, weil die App das Gerät allein nutzt.

## DSD: Was ist DoP?

DSD ist ein anderes Audioformat als das übliche PCM. Über USB lässt sich aber nur PCM übertragen.
**DoP** („DSD over PCM“) verpackt die DSD-Daten deshalb in PCM-Pakete mit einer Markierung.
Der DAC erkennt die Markierung, packt die Daten aus und spielt echtes DSD.

- **Dein DAC kann DSD** → Output **DoP** wählen.
- **Dein DAC kann kein DSD** → Output **Exclusive** wählen. DSD wird dann in PCM umgerechnet.
  Wichtig: Ein DAC ohne DSD macht aus DoP lautes Rauschen.
- Kann der DAC die DoP-Rate nicht annehmen, wechselt die App automatisch zu PCM.

Eine eigene DSD-Einstellung gibt es nicht mehr. Der Output-Modus entscheidet.

## Welche DSD-Wiedergabe bei welchem Output?

| Output | DSD-Dateien | Normale Dateien (FLAC, WAV …) |
|---|---|---|
| Shared | umgerechnet in PCM | über macOS |
| Exclusive | umgerechnet in PCM, exklusiv | bit-perfect |
| DoP | echtes DSD per DoP | bit-perfect |

Auf dem Deck steht immer, welcher Weg aktiv ist, z. B. „Exclusive · Bit-perfect“, „Exclusive · DoP“, „Exclusive · DSD→PCM“ oder mit Plugins „Exclusive · FX“.

## Plugins (Rack)

**Früher:** Sobald ein Plugin (z. B. ein EQ) im Rack war, gab die App den DAC ab und spielte über macOS
wie jede andere App (**Shared · FX**). macOS mischte andere Töne dazu und konnte die Abtastrate ändern
(eine 96-kHz-Datei kam z. B. mit 48 kHz am DAC an). Exclusive oder DoP galten dann nicht.

**Jetzt:** Hast du Exclusive oder DoP gewählt und ist ein DAC angeschlossen, behält die App den DAC auch
mit Plugins für sich (**Exclusive · FX**):

- Nur Audio Harbor spielt auf dem DAC, nichts anderes wird dazugemischt.
- Der DAC läuft auf der Abtastrate der Datei: 96 kHz kommen mit 96 kHz an.
- Das Einzige, was den Klang verändert, ist das Plugin selbst — macOS verändert nichts zusätzlich.

**Was gleich bleibt:**

- Mit Plugins ist der Ton nicht bit-perfect — das Plugin verändert ihn ja. Das ist bei jedem Player so.
- DSD mit Plugins wird zu PCM, weil Plugins nicht mit DSD arbeiten können. DoP pausiert also, solange das Rack aktiv ist.
- Leerst du das Rack, gilt ab dem nächsten Song wieder bit-perfect bzw. DoP.
- Ohne DAC oder im Shared-Modus bleibt alles wie vorher (**Shared · FX**).

Kurz: Plugins werfen dich nicht mehr auf Shared zurück. Du behältst den DAC und die richtige Abtastrate,
nur das Plugin verändert den Klang — so wie bei Audirvāna und Fidelia.

- Unterstützt werden AUv3 und klassische AU-Plugins (Stereo).- Unterstützt werden AUv3 und klassische AU-Plugins (Stereo).
  Klassische Plugins, die nicht „sandbox-safe“ sind (z. B. UAD, Valhalla), laufen in einem eigenen Prozess von macOS.

## Directories

Hier fügst du die Ordner mit deiner Musik hinzu. Die App liest nur. Sie verschiebt und verändert keine Dateien.

## License

7 Tage kostenlos ab der ersten Installation, danach einmalig freischalten.
Nach einer Neuinstallation oder auf einem neuen Mac stellst du den Kauf mit „Restore Purchases“ wieder her.

Mehr Fragen und Antworten (englisch): [FAQ](https://petergerov.github.io/audio-harbor/faq.html)
