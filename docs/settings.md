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
- **Netzwerk-Player** (UPnP / DLNA, z. B. ein Devialet Expert oder ein Streamer) stehen mit **Network**
  in derselben Liste, nach den DACs. Auswählen, und die Musik spielt dort — siehe
  [Netzwerk-Player](#netzwerk-player-der-mac-spielt-auf-einen-streamer).

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
Mit dem iPhone-Remote geht es trotzdem vom Sofa aus: Er stellt die Lautstärke am DAC selbst ein
(siehe [Remote](#remote-iphone-steuert-den-mac)).

## DSD: Was ist DoP?

DSD ist ein anderes Audioformat als das übliche PCM. Über USB lässt sich aber nur PCM übertragen.
**DoP** („DSD over PCM“) verpackt die DSD-Daten deshalb in PCM-Pakete mit einer Markierung.
Der DAC erkennt die Markierung, packt die Daten aus und spielt echtes DSD.

- **Dein DAC kann DSD** → Output **DoP** wählen.
- **Dein DAC kann kein DSD** → Output **Exclusive** wählen. DSD wird dann in PCM umgerechnet.
  Wichtig: Ein DAC ohne DSD macht aus DoP lautes Rauschen.
- Kann der DAC die DoP-Rate nicht annehmen, wechselt die App automatisch zu PCM.

Ob DSD als DSD oder als PCM rausgeht, entscheidet der Output-Modus. Einstellen kannst du nur, wie laut
umgerechnetes DSD spielt (siehe [DSD as PCM](#dsd-as-pcm-warum-ist-umgerechnetes-dsd-leiser)).

## Welche DSD-Wiedergabe bei welchem Output?

| Output | DSD-Dateien | Normale Dateien (FLAC, WAV …) |
|---|---|---|
| Shared | umgerechnet in PCM | über macOS |
| Exclusive | umgerechnet in PCM, exklusiv | bit-perfect |
| DoP | echtes DSD per DoP | bit-perfect |
| Netzwerk-Player | Full: PCM 88,2/24; Wi‑Fi friendly: 44,1/16; DSD, SACD, DoP: Datei unverändert wenn der Player DSD listet | unverändert, wenn der Player das Format annimmt, sonst 24-Bit-WAV |

Auf dem Deck steht immer, welcher Weg aktiv ist, z. B. „Exclusive · Bit-perfect“, „Exclusive · DoP“, „Exclusive · DSD→PCM“ oder mit Plugins „Exclusive · FX“. Bei einem Netzwerk-Player steht dort „Network“ / „DSD · Network“ (Datei unverändert), „PCM · Network“, „DSD→PCM · Network“, „DoP · Network“ oder „Wi‑Fi PCM · Network“.

## DSD as PCM: Warum ist umgerechnetes DSD leiser?

Settings → Output → **DSD as PCM**: **0 dB**, **+3 dB** (Standard) oder **+6 dB**.

DSD speichert keine Zahlen wie PCM, sondern nur Einsen und Nullen. Wie laut es gerade ist, steckt darin,
wie viele Einsen hintereinander kommen. Ganz ausreizen darf man das nie, sonst gerät der DSD-Wandler
außer Kontrolle. Deshalb gilt bei der SACD: **volle Lautstärke = 50 % der Möglichkeiten.**

- Bei **DoP** rechnet die App nichts um. Der DAC spielt das DSD selbst und gleicht den Abstand meistens
  intern aus. Es klingt so laut wie PCM.
- Bei der **Umrechnung in PCM** wird aus 50 % genau die Hälfte der PCM-Vollaussteuerung, also **−6 dB**.
  Das ist korrekt, aber hörbar leiser als DoP.

Die Einstellung gleicht das aus:

| Einstellung | Wirkung |
|---|---|
| **0 dB** | Exakte Umrechnung, 6 dB leiser als DoP |
| **+3 dB** | Standard. 3 dB leiser als DoP, passt für fast jede SACD ohne Übersteuern |
| **+6 dB** | So laut wie DoP. Laut gemasterte SACDs nutzen den Sicherheitsabstand teilweise aus und können übersteuern |

Die Einstellung wirkt sofort, auch im laufenden Song. Sie gilt für Shared, Exclusive · DSD→PCM und DSD mit
Plugins. **DoP bleibt unverändert.** Qualität geht dabei nicht verloren.

**Wie umgerechnet wird:** Die App filtert DSD in mehreren Stufen auf 88,2 kHz PCM herunter (DSD64 bis DSD256).
Der Frequenzgang ist **linear bis 25 kHz**, danach fällt er steil ab und ist ab **44,1 kHz um mindestens 120 dB**
gedämpft. So bleibt das starke Ultraschall-Rauschen von DSD draußen und spiegelt sich nicht in den
hörbaren Bereich. Die Filter sind phasenlinear, die Wellenform bleibt also erhalten.

## Netzwerk-Player: der Mac spielt auf einen Streamer

Statt auf einen DAC am Mac kann die App auf einen Player im Heimnetz spielen (UPnP / DLNA), z. B. einen
Devialet Expert, einen Streamer oder manche Fernseher und Soundbars. Der Mac bleibt der Player mit
Bibliothek und Warteschlange; der Netzwerk-Player holt sich die Musik über das Heimnetz.

- **Settings → Output → Device** und den Player wählen (er steht mit **Network** in der Liste). Die App
  sucht laufend nach Playern im Netz; ein neuer erscheint nach wenigen Sekunden.
- **Was gesendet wird:**

  | Datei | Geht an den Player als |
  |---|---|
  | FLAC, WAV, AIFF, ALAC, AAC, MP3, die der Player annimmt | die Datei selbst, unverändert |
  | ein Format, das der Player nicht annimmt | 24-Bit-WAV mit der Abtastrate der Datei |
  | DSF, DFF, SACD mit **Full** | PCM, 88,2 kHz / 24 Bit — mit der Einstellung *DSD as PCM* |
  | DSF, DFF, SACD mit **DSD, SACD, DoP** (wenn der Player DSD listet) | die Datei unverändert (SACD als DFF) |
  | DSF, DFF, SACD mit **Wi‑Fi friendly** | PCM, 44,1 kHz / 16 Bit |

- **Radios wechseln mit dem Gerät:** Bei einem USB-DAC stehen Shared / Exclusive / DoP. Bei einem
  Netzwerk-Player **Wi‑Fi friendly** / **Full** / **DSD, SACD, DoP** (nur wenn der Player DSD
  annimmt). Nimm Wi‑Fi friendly, wenn DSD über WLAN aussetzt.
- **Exclusive und DoP** gelten nur für DACs am Mac. Auch das Plugin-Rack wirkt beim Netzwerk-Player nicht.
- **Lückenlos** zwischen Songs, wenn der Player es kann (UPnP „SetNext“). Sonst gibt es beim Wechsel eine
  kurze Pause.
- **Lautstärke:** Der Regler am iPhone-Remote und die Lautstärketasten am iPhone stellen die Lautstärke
  des Players ein.
- **Der Mac schläft nicht ein**, solange der Player spielt. Mac und Audio Harbor müssen laufen.
- **Ist der Player aus oder nicht im Netz**, steht das unter Device. Ist er wieder da, erscheint er wieder
  in der Liste.
- **Findet die App keinen Player:** gleiches Netz (kein Gast-WLAN), Player eingeschaltet und UPnP am Player
  aktiv (beim Devialet im Configurator). Ab macOS 15 fragt macOS nach dem lokalen Netzwerk — **Erlauben**;
  sonst unter Systemeinstellungen → Datenschutz & Sicherheit → Lokales Netzwerk → Audio Harbor einschalten.
- Gehört zur Freischaltung, wie jede Wiedergabe.

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

- Auf einem Netzwerk-Player wirkt das Rack nicht: Er bekommt die Datei bzw. das umgerechnete PCM ohne Plugins.
- Unterstützt werden AUv3 und klassische AU-Plugins (Stereo).
  Klassische Plugins, die nicht „sandbox-safe“ sind (z. B. UAD, Valhalla), laufen in einem eigenen Prozess von macOS.

## Directories

Hier fügst du die Ordner mit deiner Musik hinzu. Die App liest nur. Sie verschiebt und verändert keine Dateien.

## Remote: iPhone steuert den Mac

Die Musik spielt auf dem Mac, das iPhone ist die Fernbedienung.

- **Allow Remote Control** einschalten. Der Mac ist dann im lokalen Netz sichtbar.
- **New Code** zeigt einen 6-stelligen Code, 3 Minuten gültig. Am iPhone den Mac antippen und den Code eingeben.
  Einmal gekoppelt, verbindet sich das iPhone danach ohne Code.
- **Paired devices** listet die gekoppelten iPhones. **Revoke** wirft eines raus, **Revoke All** alle.
- Am iPhone unten dieselben drei Bereiche wie am Mac: **Deck** (Wiedergabe, Queue-Sheet, Lautstärke),
  **Catalogue** (Dirs / Albums / Artists / Lists inkl. Suche) und **Settings** (Mac-Output, Sharing, Directories).
  Ein Song oder **Play all** spielt, ohne die Liste zu verlassen; der laufende Song ist markiert.
  Dirs / Albums / Artists / Lists bleiben oben, auch tief in einem Ordner — antippen führt an den Anfang.
- **Playlists und Labels vom iPhone:** Song lange drücken → **Add to Playlist…** oder **Labels…**.
  Antippen nimmt den Song auf, nochmal antippen nimmt ihn heraus; ein Haken zeigt, wo er drin ist.
  Neue Playlists und Labels lassen sich dort anlegen. Braucht Mac und iPhone ab 1.1.1.
- **Suche in Browse:** Unter Dirs / Albums / Artists / Lists sucht das Feld wie die Katalogsuche am Mac.
  Dirs findet Ordner und Dateien in allen Ordnern; ein Ordner antippen öffnet ihn und leert die Suche.
  Albums, Artists und Lists zeigen nur Einträge mit passenden Songs, darin nur diese — eine Playlist,
  deren Name passt, zeigt alle. Braucht Mac und iPhone ab 1.1.1.
- **Mac Settings vom iPhone:** Tab **Settings** — Output-Gerät, Modi / Netzwerk-Radios, DSD as PCM, Sharing,
  Directories und Index neu aufbauen. Ordner hinzufügen oder entfernen bleibt am Mac. Braucht Protokoll 3
  auf beiden Seiten.
- **Lautstärke:** Lautsprecher auf dem Deck öffnet den Regler; die Lautstärketasten am iPhone stellen die Lautstärke des Geräts ein,
  auf dem der Mac gerade spielt — den DAC selbst, wenn er eine Lautstärkeregelung hat, sonst den Mac-Ausgang.
  Der DAC regelt selbst, die Musik bleibt bit-perfect, auch in Exclusive und DoP.
  Drehst du am DAC, zieht das iPhone mit. DACs mit festem Ausgangspegel haben keine Regelung — dann gibt es
  am iPhone keinen Regler, und du regelst am Verstärker. Spielt der Mac auf einen Netzwerk-Player, regelt
  das iPhone dessen Lautstärke.
- Die Lautstärketasten steuern den Mac nur, solange die Remote-App offen ist und keine andere App auf dem
  iPhone Musik spielt. Nach dem Trennen hat das iPhone wieder seine eigene Lautstärke.

## Sharing: Musik vom Mac auf dem iPhone hören (DLNA)

Der Mac gibt die Bibliothek im Heimnetz frei, eine Player-App auf dem iPhone spielt sie selbst ab.

- **Share Library on the Network** einschalten. Der Mac heißt im Netz „Audio Harbor (Name des Macs)“.
- Auf dem iPhone eine DLNA-App öffnen, z. B. **mconnect Player Lite** (kostenlos), den Mac als Server wählen
  und durchblättern: **Albums**, **Artists**, **Directories**, **Playlists**, **Labels** — wie am Mac.
- Die App bekommt die Dateien unverändert (FLAC, WAV, AIFF, ALAC, AAC, MP3, DSF, DFF) und spielt sie selbst ab;
  ob sie DSD abspielt, hängt von der App ab. SACD-ISO-Titel werden vorher ausgepackt, der erste Start dauert
  dann einige Sekunden. DFF-Dateien mit Kapiteln werden nicht freigegeben.
- Der Mac muss an sein und Audio Harbor laufen. Solange ein Song gestreamt wird, schläft der Mac nicht ein.
- **Achtung:** Solange die Freigabe an ist, kann jeder im selben WLAN die Bibliothek sehen und abspielen —
  DLNA kennt keine Anmeldung. Nur im eigenen Netz einschalten.
- Gehört zur Freischaltung: Nach Ablauf der Testphase lässt sich noch blättern, aber nichts abspielen.
- Beim ersten Einschalten fragt macOS (ab macOS 15) nach dem lokalen Netzwerk: **Erlauben**.

## License

7 Tage kostenlos ab der ersten Installation, danach einmalig freischalten.
Nach einer Neuinstallation oder auf einem neuen Mac stellst du den Kauf mit „Restore Purchases“ wieder her.
Der iPhone-Remote ist kostenlos. Ein Kauf am iPhone schaltet den Mac derselben Apple-ID frei.

Mehr Fragen und Antworten (englisch): [FAQ](https://petergerov.github.io/audio-harbor/faq.html)
