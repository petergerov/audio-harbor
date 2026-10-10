# Audio Harbor — App Store Submission (Mac player, iPhone and iPad remote)

Eine App, zwei Plattformen, **ein** Eintrag in App Store Connect:

| Plattform | Rolle | Release |
|---|---|---|
| **macOS** | Der Player: Bibliothek, Deck, Exclusive / DoP, Rack, UPnP-Netzwerkplayer. Spielt auf dem DAC oder einem Streamer im Heimnetz. | **1.1.0** — erste Mac-Version, mit Remote-Server · danach **1.1.1** · Netzwerkplayer auf `develop` für das nächste Update |
| **iOS** (iPhone, iPad) | Die Fernbedienung: findet den Mac per Bonjour, koppelt per 6-stelligem Code, steuert Wiedergabe, Queue, Suche und die Lautstärke des DAC. Spielt selbst nichts. | **1.1.0** — erste iOS-Version, siehe [`APP_STORE_SUBMISSION_IOS.md`](APP_STORE_SUBMISSION_IOS.md) · danach **1.1.1** |

**Beide gehen in einer Einreichung raus.** Review bekommt Mac und iPhone gleichzeitig und kann den Remote gegen den Mac-Player testen, auch ohne dass der Mac schon im Store ist.

Vorgeschichte: Mac 1.0.0 (16, Branch `release/REL_1.0.0`, ohne Remote) hing im Review. Sie wird aus dem Review genommen und in App Store Connect auf **1.1.0** umbenannt (Schritte in [`APP_STORE_SUBMISSION_IOS.md` § 5](APP_STORE_SUBMISSION_IOS.md#5-app-store-connect--ablauf)). `release/REL_1.0.0` bleibt nur als Archiv. In Build 16 fehlte außerdem das Lesen der FLAC-Tags: jeder FLAC-Track stand als „Unknown Artist“ ohne Cover im Katalog.

Stand der App im Repo: Bundle `com.gerov.audioharbor.player`. **1.1.0 (17)** auf `release/REL_1.1.0` geht unverändert raus; `develop` steht auf **1.1.1 (18)** plus UPnP-Netzwerkausgabe und Bibliotheks-Sharing (siehe [What's New — Network players](#whats-new--network-players-develop)). App Sandbox aktiv, StoreKit 2 (Trial + Unlock) eingebaut. Offen sind vor allem Sandbox-Tests, die Remote-Tests ([iOS § 4](APP_STORE_SUBMISSION_IOS.md#4-testen-vor-dem-upload)), Verträge und App Store Connect.

---

## Offer (locked)

**Jeder kann die App kostenlos installieren.** Im Store ist Audio Harbor eine **Free App** — kein Kaufpreis an der Tür, kein „Get“ hinter 9,90 €. Getippt, geladen, geöffnet.

| | |
|---|---|
| App-Preis (ASC) | **Free** — alle Storefronts. Nicht „Paid App“. |
| Wer darf installieren | Jeder mit einem Apple-Account. Kein Voucher, kein Unlock vor dem Download. |
| Trial | **7 Tage voll nutzbar** ab der **ersten Installation** auf diesem Mac |
| Danach | Playback gesperrt, bis Unlock gekauft oder wiederhergestellt ist |
| IAP | Einmalig, nicht verbrauchbar (**Non-Consumable**) |
| Unlock-Preis | **9,90 €** Launch-Preis (Deutschland / Euro-Storefront); danach 14,99 €, dann 19,99 € — siehe [`marketing/COMPETITIVE.md`](marketing/COMPETITIVE.md#price-plan) |
| Abo | Nein — kein Auto-Renew, kein Account |

App Store Connect: **Pricing and Availability → Price Schedule → Free.** Die 9,90 € sitzen nur am IAP `unlock`, nicht an der App.

**Warum Non-Consumable, nicht Abo:** Audio Harbor ist lokal, ohne Login. 9,90 € ist ein Unlock, kein Mietzins. Apple hat für Non-Consumables **kein** offizielles „7-day introductory offer“ — die Trial-Uhr bauen wir selbst (StoreKit 2 + Keychain).

**Price-Tier:** In App Store Connect 9,90 € setzen. Falls die Storefront nur **9,99 €** als Standardstufe anbietet, 9,99 € nehmen und diese Datei anpassen — nicht 9,90 in der UI versprechen und 9,99 kassieren.

---

## 1. Vor dem ersten Archive — Blocker

Ohne diese Punkte Review oder Sandbox-Start nicht überstehen.

### 1.1 StoreKit

Umgesetzt in `Services/Playback/LicenseService.swift` und `Features/Settings/UnlockPanel.swift`.

- [x] StoreKit 2: Product laden, kaufen, `Transaction.currentEntitlements`, Finish, **Restore** (`AppStore.sync()`)
- [x] Product ID: `com.gerov.audioharbor.unlock` (in ASC identisch anlegen)
- [x] Trial: Zeitstempel **erste Installation** im **Keychain** (Data Protection Keychain)
- [x] Nach Tag 7 ohne Receipt: kein Playback (`PlaybackService` prüft `license.canPlay`); Catalogue / Settings / Restore bleiben erreichbar
- [x] Preis aus StoreKit (`displayPrice`), nicht hardcodiert
- [x] StoreKit Configuration File für lokale Tests: `AudioHarbor/Resources/AudioHarbor.storekit`
- [x] Debug-Buttons „expire / reset trial“ nur unter `#if DEBUG`, nicht im Release
- [ ] Sandbox-Apple-ID: Trial ablaufen lassen, kaufen, App löschen, Restore

Gate nach Ablauf (Vorschlag, nicht verhandelbar für Review):

| Oberfläche | Ohne Unlock nach 7 Tagen |
|---|---|
| Catalogue, Suche, Ordner, Playlists ansehen | Ja |
| Play / Exclusive / DoP / Rack | Nein — Unlock-Sheet |
| Restore Purchases | Immer |

Während der 7 Tage: volle App, kein Wasserzeichen, kein Nagscreen alle 30 Sekunden. Ein ruhiger Hinweis in Settings („Trial · n days left“) reicht.

### 1.2 Mac App Store Sandbox

MAS **erzwingt** App Sandbox. `AudioHarbor/Resources/AudioHarbor.entitlements` ist gesetzt:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.files.bookmarks.app-scope</key>
<true/>
<key>com.apple.security.device.audio-input</key>
<false/>
```

Zusätzlich prüfen (AU-Rack / Classic AU außerhalb des Containers):

- Leserechte auf `/Library/Audio/Plug-Ins/` und `~/Library/Audio/Plug-Ins/` nur wenn Review ohne Temporary Exception scheitert
- Hardened Runtime bleibt an (`ENABLE_HARDENED_RUNTIME` ist schon gesetzt)

Ordnerzugriff läuft über `NSOpenPanel` / `fileImporter` + security-scoped Bookmarks — das passt zum Sandbox-Modell. Nicht die ganze Platte freischalten.

`read-write` statt `read-only` nur für den Playlist-Export (M3U8 per `NSSavePanel`). Musikordner-Bookmarks werden mit `securityScopeAllowOnlyReadAccess` angelegt. Falls Review fragt: „Users export playlists as M3U8 files to a location they choose in the save panel.“

### 1.3 Version, Signing, Privacy-URL

- [x] Marketing-Version **1.1.0** — in `project.yml` gesetzt, landet über XcodeGen im Projekt. Aktueller Build **17** (`CURRENT_PROJECT_VERSION`), jeder Upload +1
- [x] Build-Nummer: macOS verlangt eine höhere Build-Nummer als jede bisher hochgeladene (Build 16 von 1.0.0) — Upload mit Build 1 scheiterte mit Fehler 90061. Daher Build **17**, für iOS ebenso gültig. Nie wieder unter die höchste hochgeladene Nummer zurücksetzen.
- [ ] Team: Apple Developer Program, Signing **Apple Distribution** / Mac App Store (nicht Developer ID)
- [x] Privacy Policy **live per HTTPS**: <https://petergerov.github.io/audio-harbor/privacy.html>
      (GitHub Pages, Quelle `main` + `/docs`). Geprüft: 200, HTTP wird auf HTTPS umgeleitet, Inhalt identisch mit `main`.
- [x] Kauf-Absatz steht in der Policy: Apple wickelt die Zahlung ab, Receipt bleibt bei Apple, kein Account, Trial-Datum im Keychain

### 1.4 Build-Stand

| Build | Inhalt |
|---|---|
| 9 | Hauptfenster im Window-Menü |
| 10 | DoP-Bitreihenfolge korrigiert (Rauschen bei DoP, z. B. SACD ISO); DoP-Aussetzer behoben (größerer HAL-IO-Puffer ~50 ms, DSD-Daten werden vorausgelesen) |
| 11 | DSD-Strategie entfernt, der Output-Modus entscheidet; Exclusive spielt DSD exklusiv als PCM (Umrechnung vorab im Hintergrund); DoP nur an externe DACs (USB, Thunderbolt, FireWire, PCI); AU-Plugins ohne `sandboxSafe` laden out-of-process; kein Absturz mehr beim Start mit Plugin-Rack |
| 12 | DAC bleibt über Titelwechsel exklusiv (kein DSD↔PCM-Umschalten pro Titel, das manche DACs per USB-Reset quittieren); solange die App den DAC hält, ist er das Ziel statt des System-Standards; Play nach fehlgeschlagenem Laden lädt den Titel neu |
| 13 | Exclusive/DoP nur mit externem DAC (sonst Shared, Lautstärketasten gehen); Settings grauen sie ohne DAC aus, zeigen Shared und wählen beim Anstecken wieder die vorherige DAC-Einstellung; M3U/M3U8-Import und -Export (Entitlement `user-selected.read-write`); neues App-Icon; FAQ-Seite `docs/faq.html` |
| 1.1.0 (1) | iPhone- und iPad-Remote (iPad mit derselben Oberfläche wie das iPhone, mittig): Remote-Server am Mac (Bonjour, Pairing-Code, Token), DAC-Lautstärke per Remote; FLAC-Tags und -Cover werden gelesen, Cover-Dateien im Ordner (`cover.jpg`, `folder.jpg`, …) als Rückfall; Alben nach Album-Artist gruppiert, Sampler ohne Tag bleiben ein Album; größeres Cover im Deck, auch bei Tonband und Receiver; Rechtsklick „Add to Playlist“ / „Labels“ für Ordner, Alben, Künstler und die Deck-Queue; Klick spielt ohne Sprung zum Deck (⌘-Klick, „Play and Show Deck“, ⌘3). Der Katalog wird beim ersten Start einmal neu eingelesen (neues Schema). |
| 1.1.1 (18) | Remote-Protokoll 2: Playlists und Labels vom iPhone/iPad (`trackOptions`, `editTrack` — hinzufügen, herausnehmen, neu anlegen); eine Nachricht, die der Mac nicht kennt, bekommt einen Fehler statt die Verbindung zu trennen. Remote: Abspielen bleibt in der Liste, der laufende Song ist markiert; Dirs / Albums / Artists / Lists bleiben beim Durchklicken sichtbar. Suchleiste darunter wie die Katalogsuche am Mac (`BrowseRequest.query`): Dirs über alle Ordner, Albums / Artists / Lists nur mit passenden Songs. Der Mac merkt sich seinen Remote-Port über Neustarts; das iPhone meldet einen nicht erreichbaren Mac, statt endlos zu laden. DSD→PCM neu: mehrstufige phasenlineare FIR-Filter statt Butterworth 4. Ordnung bei 20 kHz (der war bei 20 kHz schon −3 dB und ließ DSD-Rauschen in den Hörbereich spiegeln), jetzt linear bis 25 kHz, ab 44,1 kHz ≥ 120 dB Dämpfung. Settings → Output → *DSD as PCM*: 0 / +3 / +6 dB, Standard +3 dB — umgerechnetes DSD war 6 dB leiser als DoP, weil SACD-0-dB nur 50 % Aussteuerung ist. |
| develop (nach 1.1.1) | UPnP / DLNA-Netzwerkausgabe: Renderer unter **Network Players**; Radios **Wi‑Fi friendly** / **Full** / **DSD, SACD, DoP** (ausgegraut bis der Player DSD listet); native DSF/DFF/SACD wenn möglich, sonst PCM; Library Sharing (Settings → Sharing). Siehe [`docs/UPNP.md`](docs/UPNP.md). |

- [ ] Vor dem Upload mit USB-DAC testen: DSF, DFF und SACD ISO in **DoP** (kein Rauschen, keine Aussetzer), PCM in **Exclusive**
- [ ] 1.1.1, DSD als PCM (Shared, Exclusive, mit Plugin): DSD64 und DSD128/256 spielen sauber ohne Aussetzer; *DSD as PCM* 0 → +3 → +6 dB im laufenden Song hörbar lauter, +3 dB etwa 3 dB unter DoP am selben DAC; Spulen ohne Knacken; DoP-Pegel unverändert

### 1.5 App Store Connect (Verträge)

- [ ] Paid Applications Agreement akzeptieren
- [ ] Bank / Tax / W-8 oder EU-Steuer
- [ ] Paid Apps + IAP sind erst buchbar, wenn der Vertrag **Active** ist (sonst „Missing Metadata“ am Produkt)

---

## 2. App Store Connect — App anlegen

Erledigt: Der Eintrag existiert seit der Mac-1.0.0-Einreichung. Zur Erinnerung, so wurde er angelegt:

1. [App Store Connect](https://appstoreconnect.apple.com) → My Apps → **+** → New App
2. Platforms: **nur macOS** (iOS nicht ankreuzen)
3. Name: **Audio Harbor**
4. Primary language: **English (U.S.)**
5. Bundle ID: `com.gerov.audioharbor.player` (in Developer Portal anlegen, falls fehlend)
6. SKU: `gerov-audio-harbor-mac`
7. User Access: Full Access
8. **Pricing and Availability:** Price = **Free**. Availability = die Länder, in denen ihr listen wollt. Nicht versehentlich 9,90 € als App-Preis setzen.

Das iPhone kommt dazu, indem **dieselbe** App um die Plattform **iOS** erweitert wird, keine zweite App — siehe [`APP_STORE_SUBMISSION_IOS.md` § 5](APP_STORE_SUBMISSION_IOS.md#5-app-store-connect--ablauf). Gleiche Bundle ID auf beiden Plattformen = **Universal Purchase**: ein Eintrag, ein Preis, ein IAP `unlock`, gültig für alle Geräte derselben Apple-ID.

---

## 3. In-App Purchase anlegen

App → Monetization → In-App Purchases → **Non-Consumable**

| Feld | Wert |
|---|---|
| Reference Name | Audio Harbor Unlock |
| Product ID | `com.gerov.audioharbor.unlock` |
| Price | 9,90 € (DE); übrige Storefronts von Apple ableiten lassen |
| Availability | Alle Länder, in denen wir listen |

**Localization (EN, Pflicht):**

- Display Name: `Unlock Audio Harbor`
- Description: `One-time unlock after the 7-day trial. Play your local library — Exclusive, DoP, and the plugin rack included.`

**Localization (DE, empfohlen):**

- Anzeigename: `Audio Harbor freischalten`
- Beschreibung: `Einmaliger Kauf nach 7 Tagen Probe. Lokale Bibliothek spielen — inklusive Exclusive, DoP und Plugin-Rack.`

Review screenshot: Paywall mit Preis und Restore — [`docs/images/review-information.png`](docs/images/review-information.png) (1280 × 800, kein Fensterrahmen). In App Store Connect unter dem IAP **Review Information → Screenshot** hochladen. Review notes: Sandbox-Schritte (Trial umgehen per StoreKit-Config oder Hinweis, wie Reviewer 7 Tage überspringt — z. B. Debug-Override nur in `#if DEBUG`, nicht im Release).

---

## 4. Listing-Copy (English — so paste)

**Name:** Audio Harbor  
**Subtitle:** Local audiophile player  
**Category:** Music  
**Secondary:** Entertainment (optional)

**Promotional text** (up to 170):

```
Free to install. Seven days full use, then €9.90 once — no subscription. Local folders, bit-perfect Exclusive and DoP, UPnP network players, AU and AUv3 on the Deck. No account.
```

**Description:**

```
Audio Harbor is a local audiophile player for Mac. Add the folders you already have. Browse a quiet catalogue. Hear the file.

Free to install for everyone. Seven days full use after you first install. Then a one-time unlock (€9.90). No subscription. No account.

Shared is the everyday path — other Mac sound still works. Exclusive takes over a USB DAC for bit-perfect playback and sample-rate match; DSD is converted to PCM, flat to 25 kHz, with a level setting so it plays as loud as DoP. DoP does the same and sends DSD files to a DSD-capable DAC as real DSD.

Play to a UPnP / DLNA network player on your home network — a Devialet Expert, a streamer, some soundbars. Network Players sit apart from This Host. The radios switch with the pick: Shared, Exclusive and DoP for a USB DAC; Wi‑Fi friendly, Full, or DSD, SACD, DoP when the player lists DSD — then those files go to it untouched. You can also share the library so a DLNA app such as mconnect plays it on your iPhone.

AUv3 inserts (and classic AU on Mac) live on the Deck rack. The rack uses Shared. Exclusive stays bit-perfect when the rack is empty.

What you get
• Folders you pick — security-scoped, remembered
• Catalogue by directory, album, and artist, with search, playlists, and labels
• FLAC, ALAC, WAV, AIFF, AAC, MP3, DSF, DFF
• SACD ISO — stereo tracks from the disc TOC, including DST-compressed areas
• Shared, Exclusive, and DoP for USB DACs — explained in plain language
• UPnP / DLNA network players — Wi‑Fi friendly, Full, or native DSD when supported
• Library sharing as a DLNA music server
• Import and export M3U / M3U8 playlists
• Optional AU / AUv3 rack on Shared
• Free iPhone and iPad remote — browse, queue, and set your DAC's or network player's volume from the couch

What you do not get
• Streaming services or an account
• Bit-perfect over Bluetooth, AirPlay, or built-in speakers (those stay Shared)
• A kitchen-sink mixer

Privacy: nothing about your library leaves the Mac, except what you choose to play or share on your own local network. See the Privacy Policy.

Restore Purchases is in Settings if you reinstall or switch Macs with the same Apple ID.
```

**Keywords** (100 characters, comma-separated, no spaces after commas if you need the room):

```
audiophile,FLAC,DSD,DoP,bit-perfect,DAC,UPnP,DLNA,local,player,AUv3,SACD
```

**Support URL:** `https://github.com/petergerov/audio-harbor/issues` (oder eine Support-Seite auf der Marketing-Domain)  
**Marketing URL:** Homepage (`docs/index.html` muss live HTTPS sein)  
**Privacy Policy URL:** `https://petergerov.github.io/audio-harbor/privacy.html`

**Age rating:** 4+ — keine user-generated chats, keine Werbung, keine unrestricted web.

**Copyright:** `2026 Gerov`

### What's New in This Version (1.1.0)

App Store Connect zeigt das Feld nur bei einem **Update** einer schon veröffentlichten Version. Mac 1.0.0 ging nie live, also fehlt das Feld bei 1.1.0 vermutlich — dann den Text für die Homepage und die GitHub-Release-Notes nutzen (wer 1.0.0 von GitHub hat, sieht hier die Änderungen). Ab 1.1.1 gehört er ins Feld.

```
Control Audio Harbor from your iPhone or iPad. The new remote is free.

• iPhone and iPad remote: browse, search, queue, and play from the couch. Turn on Settings → Remote → Allow Remote Control, pair once with a six-digit code, and the remote reconnects on its own.
• Set your DAC's volume from the remote, with the slider or the volume buttons. In Exclusive and DoP the DAC changes its own level, so playback stays bit-perfect.
• FLAC tags and embedded cover art are now read. Cover images in the folder (cover.jpg, folder.jpg …) fill in where a file has none.
• Albums are grouped by album artist. Compilations without tags stay one album.
• A larger cover on the Deck, in every style.
• Add to Playlist and Labels from the right-click menu on directories, albums, artists, and the Deck queue.
• Clicking plays without leaving the list. Play and Show Deck or ⌘-click takes you to the Deck.

On first launch Audio Harbor reads your library once more to pick up the new tags.
```

### What's New in This Version (1.1.1)

Erstes Update nach 1.1.0 — das Feld erscheint, sobald 1.1.0 live ist. Mac und iOS gehen wieder gemeinsam raus: die neuen Remote-Funktionen brauchen beide Seiten auf 1.1.1.

```
The iPhone and iPad remote now files your music.

• Add a song to a playlist or take it out, and set or clear its labels, right from the remote. Long-press a song and choose Add to Playlist or Labels.
• Search on the remote works like the catalogue search on the Mac: across every directory, or for albums, artists, and playlists with a matching song.
• Playing a song or a whole album from the remote keeps you in the list, with the song that plays marked.
• The remote finds the Mac again more reliably after the Mac restarts.
• DSD converted to PCM (Shared and Exclusive) sounds cleaner: flat to 25 kHz, with DSD's ultrasonic noise kept out of the audible band.
• New in Settings → Output: DSD as PCM, 0 / +3 / +6 dB. Converted DSD used to play 6 dB quieter than DoP; it now plays 3 dB louder by default, or as loud as DoP at +6 dB.

Update the remote too: playlists, labels, and search need version 1.1.1 on the Mac and on the iPhone or iPad.
```

### What's New — Network players (`develop`)

Copy for the next Mac update after 1.1.1 (bump marketing version when you cut the release). iOS remote needs no change for this feature.

```
Play to a network streamer from Audio Harbor on your Mac.

• UPnP / DLNA players on your home network appear under Network Players, separate from This Host.
• Output radios switch with the device: Shared, Exclusive and DoP stay for USB DACs; network players get Wi‑Fi friendly, Full, and DSD, SACD, DoP when the player lists DSD.
• Files the player accepts go untouched. DSF, DFF and SACD go native when supported, as 88.2 kHz PCM on Full, or as CD-rate PCM on Wi‑Fi friendly.
• Share Library on the Network (Settings → Sharing) so a DLNA app such as mconnect can browse and play your catalogue.
• The iPhone remote sets the network player's volume. The Mac stays awake while it plays.
```

---

## 5. Screenshots (Mac)

App Store Connect verlangt mindestens **einen** Satz. Sinnvoll:

| Größe | Typisches Display |
|---|---|
| 1280 × 800 | 13″ / 16:10 |
| 2560 × 1600 | Retina 13″ |

Fertiger Satz (September 2026, Build 16): [`marketing/app-store/`](marketing/app-store/) —
`mac-2560x1600/` (Retina) und `mac-1280x800/`, je 5 Bilder, opak (kein Alphakanal), ohne Hardware-Rahmen:

1. **The Deck** — „Open a folder. Hear the file.“ (Plattenspieler, Queue rechts)
2. **Catalogue** — „The music you already own, by album and artist.“
3. **Directories** — „Browse your disks as they are. Search all of them at once.“
4. **AU and AUv3** — „Your own plugins, right on the Deck.“ (Receiver + VU, AUNBandEQ im Rack, Shared · FX)
5. **Output** — „Shared, Exclusive or DoP for a USB DAC; network players get their own radios.“

Texte stehen in `marketing/app-store/screenshots.txt`, die Rohaufnahmen in `raw/`;
`marketing/app-store/build.sh` setzt alles neu zusammen. Kein Preis im Listing-Bild, weil der
Preis noch in Stufen steigen soll.

Offen: Das IAP-Review-Bild `docs/images/review-information.png` zeigt noch das alte Design
(alte Seitenleiste, Untertitel). Neu aufnehmen braucht einen gesperrten Zustand (Trial vorbei,
nicht freigeschaltet).

Caption-Stil: ein Satz, Englisch, kein „Best ever!!!“.

App-Icon: Asset Catalog ist vollständig (1024 + Mac-Größen). MAS-Icon ohne Transparenz-Probleme im 1024er.

---

## 6. Review notes (an Apple)

```
Audio Harbor plays local audio files the user adds via a folder picker.

Trial: 7 days from first launch (Keychain). After that, playback requires the non-consumable IAP “Unlock Audio Harbor” (€9.90). Restore Purchases is in Settings.

To review past the trial immediately: use the sandbox account; or in the attached StoreKit notes, purchase the unlock. There is no demo login — there are no accounts.

Exclusive / DoP need an external USB DAC. Shared works on built-in speakers.

SACD ISO: stereo area only. Tracks come from the Scarlet Book TOC. Uncompressed DSD and DST-compressed tracks both play: DST is decoded with Harbor’s own MPEG-4 DST decoder to a cached DFF, then the same DoP / PCM path as DSF. The first play of a DST track may pause while that cache is built. Multi-channel SACD areas, CUE sheets, and format conversion are not in this version.

Please use your own files or a short CC clip. Do not require ripped commercial SACD images for review.

iPhone remote: this submission also contains the iOS app, a remote for this Mac app (same record, Universal Purchase). The Mac listens on the local network only so the user's own paired iPhone can control playback (com.apple.security.network.server / network.client). See the iOS review notes for the pairing steps.

Network players (Mac): UPnP / DLNA MediaRenderers on the local network can be picked as the output (SSDP discovery). The Mac serves audio over HTTP on the LAN only; nothing leaves the home network. Optional library sharing (Settings → Sharing) exposes the catalogue as a UPnP MediaServer for DLNA apps on the same network. Local Network permission may be requested on macOS 15+.
```

Demo-Musik: ein kurzes **eigenes** oder CC-File im Review-Ordner erwähnen, oder Reviewer eigene Dateien nutzen lassen. Keine gerippten Major-Label-ISOs mitschicken.

---

## 7. Archive & Upload

```bash
# Optional, wenn ihr XcodeGen nutzt
xcodegen generate

# In Xcode: Scheme AudioHarbor → Any Mac (Apple Silicon) oder My Mac
# Product → Archive (Release)
# Organizer → Distribute App → App Store Connect → Upload
```

- Zweimal archivieren: einmal **Any Mac**, einmal **Any iOS Device (arm64)** — siehe [`APP_STORE_SUBMISSION_IOS.md` § 10](APP_STORE_SUBMISSION_IOS.md#10-archive--upload)
- Nach Processing: jeden Build seiner Version 1.1.0 zuweisen (Mac-Build → macOS, iOS-Build → iOS), IAP an die Mac-Version anhängen (IAP muss **Ready to Submit** sein)
- Export Compliance: `ITSAppUsesNonExemptEncryption = NO` steht in Info.plist / project.yml (HTTPS + Hashing only). Damit fällt „Missing Compliance“ nach dem Upload weg. Nur ändern, wenn ihr eigene nicht-exempt Verschlüsselung einbaut.

---

## 8. App-Privacy-Fragen (ASC)

Ehrlich, passend zu [`docs/privacy.html`](docs/privacy.html):

| Daten | Antwort |
|---|---|
| Tracking | Nein |
| Purchase History | Ja — Apple (StoreKit), nicht von uns an Dritte |
| Audio files / library | Nur on-device, nicht collected by developer |
| Diagnostics | Nur wenn ihr später opt-in Crashreports anmacht; heute: nein |
| Contact Info | Nein |

Data Used to Track You: **No**.

---

## 9. Was Review oft ablehnt (bei diesem Offer)

- Trial, die sich durch Löschen der App endlos neu startet → Keychain, nicht nur UserDefaults
- „7 Tage gratis“ in Screenshots, aber IAP fehlt oder anderer Preis
- Hardcodiertes „€9.90“ statt `Product.displayPrice` (Guideline 3.1.1 / lokale Währung)
- Kein Restore
- Sandbox ohne `user-selected` Files: Catalogue leer, Reviewer kann nichts spielen
- Exclusive als „bit-perfect on Mac speakers“ in der Description
- AU-Plugins, die im Sandbox-Review crashen — Fallback-Text, nicht hartes Fail

---

## 10. Nach dem Live-Gang

- [ ] Homepage-CTA von GitHub auf Mac App Store umbiegen (`docs/index.html`, `marketing/MARKETING.md`)
- [x] Privacy-URL final — <https://petergerov.github.io/audio-harbor/privacy.html>
- [ ] Support-URL final
- [ ] Phased Release optional

---

## 11. iPhone- und iPad-Remote

Steht jetzt in [`APP_STORE_SUBMISSION_IOS.md`](APP_STORE_SUBMISSION_IOS.md): Code-Blocker, Tests, App-Store-Connect-Ablauf (Mac 1.0.0 umbenennen, iOS-Plattform hinzufügen), Listing-Copy, Screenshots, Review Notes, Privacy, Archive & Upload.

---

## Identität (Ist-Stand Xcode)

| | |
|---|---|
| Display name | Audio Harbor |
| Bundle ID | `com.gerov.audioharbor.player` — macOS **und** iOS (Universal Purchase) |
| Plattformen | macOS = Player · iOS = Remote (ab 1.1.0) |
| Category (Info.plist) | `public.app-category.music` |
| macOS deployment | 14.0 |
| iOS deployment | 17.0 |
| Remote | Bonjour `_audioharbor._tcp`, TCP im lokalen Netz, 6-stelliger Code (3 min gültig) |
| App-Preis | Free — jeder darf installieren |
| IAP product | `com.gerov.audioharbor.unlock` |
| Trial | 7 Tage ab erster Installation — nur am Mac; der Remote auf iPhone und iPad ist frei |
| Unlock | 9,90 € einmalig |
