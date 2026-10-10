# Audio Harbor — App Store Submission iOS (iPhone and iPad remote)

Die iOS-App ist die **Fernbedienung** für Audio Harbor am Mac: findet den Mac per Bonjour, koppelt per 6-stelligem Code, steuert Wiedergabe, Queue, Suche und die Lautstärke des DAC. Sie spielt selbst nichts. Sie läuft auf iPhone **und iPad**; alles hier gilt für beide, wo nicht anders steht.

iOS 1.1.0 ist die **erste iOS-Version** und geht in **derselben** Einreichung wie Mac 1.1.0 raus. Danach folgt **1.1.1 (18)**, wieder mit dem Mac zusammen: Playlists, Labels und Suche vom Remote ([What's New 1.1.1](#whats-new-in-this-version-111), Tests in [§ 4](#4-testen-vor-dem-upload)). Review bekommt Mac und iPhone gleichzeitig und kann den Remote gegen den Mac-Player testen, auch ohne dass der Mac schon im Store ist. Alles zum Mac-Player steht in [`APP_STORE_SUBMISSION.md`](APP_STORE_SUBMISSION.md).

---

## Eckdaten

| | |
|---|---|
| Display name | Audio Harbor |
| Bundle ID | `com.gerov.audioharbor.player` — dieselbe wie am Mac (Universal Purchase) |
| Target | `AudioHarbor` — ein Target für macOS und iOS, Branch `release/REL_1.1.0` aus `develop` |
| Version | `MARKETING_VERSION` **1.1.0** — eine Versionsnummer für beide Plattformen. Eine erste iOS-Version muss nicht 1.0 heißen. Auf `develop` schon **1.1.1**. |
| Build | `CURRENT_PROJECT_VERSION` **17** für 1.1.0, **18** für 1.1.1 (siehe [§ 3](#3-version-build-signing)) |
| Geräte | iPhone und iPad (`TARGETED_DEVICE_FAMILY: "1,2"`) |
| iOS deployment | 17.0 |
| Remote | Bonjour `_audioharbor._tcp`, TCP im lokalen Netz, 6-stelliger Code (3 min gültig), danach Token. Protokoll 1 in 1.1.0, **2** ab 1.1.1 (Playlists, Labels, Suche in Catalogue), **3** auf `develop` (Mac Settings vom Settings-Tab) |
| App-Preis | Free — für den ganzen Eintrag |
| IAP product | `com.gerov.audioharbor.unlock` (Non-Consumable, 9,90 €) |
| Trial | Nur am Mac. Der Remote auf iPhone und iPad ist frei und hat keine eigene Sperre. |
| Signing | Automatic, Team `C9LBGZNZ6P`, Apple Distribution |
| Entitlements | `AudioHarbor/Resources/AudioHarbor-iOS.entitlements` (leeres `<dict/>`) |

---

## 1. Was rausgeht

| | Mac 1.1.0 | iOS 1.1.0 |
|---|---|---|
| Neu | Remote-Server (Settings → Remote → *Allow Remote Control*), Pairing, DAC-Lautstärke per Remote | Erste iOS-Version: Remote für den Mac |
| Branch | `release/REL_1.1.0` aus `develop` | derselbe Branch, dasselbe Target |
| Version | `MARKETING_VERSION` 1.1.0 | ebenfalls 1.1.0 |
| Build | `CURRENT_PROJECT_VERSION` 17 | derselbe Build-Wert ist ok |

Der Remote ist **kostenlos** und hat keine eigene Trial-Sperre. Die Trial-Uhr und die Sperre gibt es nur auf dem Mac, weil nur dort Musik spielt. Das Unlock-Panel in den iPhone-Settings kauft oder stellt denselben IAP wieder her. Durch Universal Purchase schaltet ein Kauf am iPhone den Mac derselben Apple-ID frei (am Mac danach *Restore Purchases*, falls der Status nicht sofort springt).

---

## 2. Blocker im Code vor dem iOS-Archive

- [x] **`UIBackgroundModes` → `audio` aus `AudioHarbor/Resources/Info.plist` entfernt.** Der Remote spielt kein Audio; Hintergrund-Audio ohne Audio ist ein sicherer Ablehnungsgrund (Guideline 2.5.4). Auf dem Mac ist der Key wirkungslos, er kann also ganz raus.
- [x] **`NSLocalNetworkUsageDescription` neutral formuliert.** Der Text erscheint auch auf dem iPhone, dort passte „on this Mac“ nicht. Jetzt: `Audio Harbor uses your local network so your iPhone can find your Mac and control playback on it.`
- [x] **Entitlements pro Plattform.** `AudioHarbor.entitlements` enthält macOS-Schlüssel (`com.apple.security.*`), die ein iOS-Upload ablehnen kann (ITMS-90046). iOS signiert jetzt mit `AudioHarbor/Resources/AudioHarbor-iOS.entitlements` (leeres `<dict/>` — Bonjour braucht kein Entitlement, nur `NSBonjourServices`), gesetzt über `CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]` in `project.yml`.
- [x] **Mac-Entitlements für 1.1.0**: `com.apple.security.network.server` + `network.client` stehen in `project.yml` (in 1.0.0 nicht). Ohne sie findet das iPhone den Mac nicht. Falls Review fragt: „The Mac listens on the local network only so the user’s own paired iPhone can control playback.“
- [x] **iPhone und iPad.** Das iPad zeigt genau die iPhone-Oberfläche (Deck · Catalogue · Settings unten), mittig auf höchstens 600 pt Breite — auch Discovery und Pairing. Alle vier Ausrichtungen sind erlaubt (Pflicht für iPad-Multitasking). Achtung: iPad-Unterstützung lässt sich nach dem ersten Release **nicht mehr entfernen**.
- [x] **Kein Vision Pro.** `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO` — die App erscheint nicht als „Designed for iPad“ auf visionOS.
- [x] **Gesperrter Mac sichtbar.** Ist die Trial am Mac abgelaufen, meldet der Snapshot `playbackLocked`, und das iPhone zeigt auf dem Deck: „The trial on … has ended. Unlock Audio Harbor in its Settings to keep playing.“
- [x] **Export Compliance:** `ITSAppUsesNonExemptEncryption = NO` in Info.plist / `project.yml` — gilt auch für den iOS-Build.

---

## 3. Version, Build, Signing

- [x] Marketing-Version **1.1.0** in `project.yml`, landet über XcodeGen im Projekt.
- [x] Build **17**. Der erste Upload mit Build 1 scheiterte mit Fehler **90061** („CFBundleVersion [1] … must contain a higher version than that of the previously uploaded version [16]“), weil Mac 1.0.0 schon als Build 16 hochgeladen war. Für iOS ist 17 ebenso gültig. Ab jetzt jeder Upload +1, nie unter die höchste hochgeladene Nummer zurücksetzen. Falls 17 als „bereits vorhanden“ abgelehnt wird: 18.
- [ ] Signing: Automatic, Team `C9LBGZNZ6P`, **Apple Distribution**. Die Bundle ID ist dieselbe wie am Mac; Xcode legt das iOS-Provisioning-Profil beim ersten Archive an.
- `xcodegen generate` entfernt Versionseinträge, die Xcode direkt im Target gesetzt hat; maßgeblich ist `project.yml`.

---

## 4. Testen vor dem Upload

- [ ] Echtes iPhone + Mac im selben WLAN: Mac findet sich, Pairing mit Code, Reconnect ohne Code (Token), *Revoke* am Mac wirft das iPhone raus
- [ ] Dasselbe mit einem iPad: Hoch- und Querformat, Split View, Lautstärketasten am iPad
- [ ] Local-Network-Abfrage auf dem iPhone erscheint beim ersten Suchen; nach *Ablehnen* zeigt die App einen verständlichen Zustand
- [ ] Play / Pause / Skip / Seek / Queue / Catalogue-Suche / Ordner, Album, Playlist starten
- [ ] Untere Tabs: Deck · Catalogue · Settings
- [ ] Lautstärke: Lautsprecher auf dem Deck öffnet den Regler; Lautstärketasten am iPhone ändern den DAC (Exclusive **und** DoP). DAC ohne Hardware-Lautstärke: durchgestrichener Lautsprecher
- [ ] Lautstärketasten mit Musik einer anderen App auf dem iPhone: Tasten gehören dann dieser App. Nach dem Trennen hat das iPhone wieder seine alte Lautstärke
- [ ] App in den Hintergrund und zurück: Verbindung kommt wieder, Tasten gehen wieder
- [ ] Mac mit abgelaufener Trial: iPhone zeigt den Sperr-Hinweis auf dem Deck

**Zusätzlich für 1.1.1** (Mac und iPhone beide auf 1.1.1):

- [ ] Song lange drücken (Catalogue, Queue) → *Add to Playlist…*: hinzufügen, Haken erscheint; nochmal antippen nimmt ihn heraus, die Verbindung bleibt. Neue Playlist anlegen. Am Mac stimmt die Playlist
- [ ] *Labels…*: Label setzen, entfernen, neues anlegen; am Mac in der Trackzeile sichtbar
- [ ] *Playlist and Labels* auf dem Deck: dieselben zwei Punkte für den laufenden Song
- [ ] Song und *Play all* antippen: bleibt in der Liste, der laufende Song ist bernsteinfarben mit Lautsprecher; nochmal antippen pausiert
- [ ] In Dirs tief in Ordner gehen: Dirs / Albums / Artists / Lists bleiben oben, Antippen führt an den Anfang
- [ ] Suche unter Catalogue: Dirs findet Ordner und Dateien in allen Ordnern (Ordner antippen öffnet ihn und leert die Suche); Albums / Artists / Lists zeigen nur Einträge mit passenden Songs und darin nur diese; eine Playlist, deren Name passt, zeigt alle Songs. Treffer antippen bleibt geöffnet
- [ ] Mac-App beenden (auch per Xcode-Stop) und neu starten: das iPhone verbindet wieder (gleicher Port). Mac aus: das iPhone zeigt „Can't reach …“ statt endlos zu laden
- [ ] iPhone 1.1.1 mit Mac 1.1.0: Menü zeigt nur *Play*, keine Suchleiste in Catalogue, nichts bricht ab. iPhone 1.1.0 mit Mac 1.1.1: verbindet und steuert wie bisher
- [ ] Unlock-Panel in den iPhone-Settings (Discovery): Kauf und Restore mit Sandbox-Apple-ID; danach am Mac *Restore Purchases*

**Zusätzlich für Remote-Tabs / Settings (Mac und iPhone mit Protokoll 3):**

- [ ] Settings-Tab: Output-Gerät wählen (scrollbare Liste, lange Namen), Shared/Exclusive/DoP bzw. Netzwerk-Radios, DSD as PCM, Sharing, Directories + Rebuild Index
- [ ] Deck: Queue-Sheet, kein Suchfeld; Receiver-Look nicht im Style-Picker
- [ ] Settings-Panels nutzen die volle iPhone-Breite

---

## 5. App Store Connect — Ablauf

1. **Mac 1.0.0 aus dem Review nehmen:** Versionsseite → **Remove from Review**. Die Version wird wieder bearbeitbar; Texte, Screenshots und der angehängte IAP bleiben.
2. **Versionsnummer der Mac-Version auf 1.1.0 ändern.** Eine nicht veröffentlichte Version lässt sich umbenennen — keine zweite Mac-Version anlegen. Build 16 von der Version lösen.
3. My Apps → **Audio Harbor** → links unter der Plattform-Liste **„+ Add Platform“** → **iOS**. Keine neue App anlegen — sonst gibt es kein Universal Purchase. Es entsteht eine eigene **iOS-App-Version 1.1.0** mit eigener Beschreibung, eigenen Keywords und eigenen Screenshots ([§ 6](#6-listing-copy-english--so-paste), [§ 7](#7-screenshots)).
4. Beide Builds hochladen ([§ 10](#10-archive--upload)), je der passenden Version zuweisen (iOS-Build → iOS 1.1.0, Mac-Build → macOS 1.1.0).
5. **Add for Review** an beiden Versionen → **eine** Submission mit Mac 1.1.0 + iOS 1.1.0. Der IAP geht mit der Mac-Version zum ersten Mal ins Review, muss also dort angehängt und **Ready to Submit** sein.
6. IAP-Beschreibung prüfen — sie erscheint jetzt auch auf dem iPhone. Vorschlag EN: `One-time unlock after the 7-day trial. Plays your local library on your Mac — Exclusive, DoP, and the plugin rack included.`

**Gilt für den ganzen Eintrag** (einmal gesetzt, nicht pro Plattform): Name, Preis (Free), IAP, App Privacy, Altersfreigabe, Kategorie.
**Pro Plattform**: Untertitel, Promotional Text, Description, Keywords, Screenshots, Review Notes, Build.

---

## 6. Listing-Copy (English — so paste)

**Name:** Audio Harbor (ganzer Eintrag)
**Subtitle:** `Remote for the Mac player`
**Category:** Music (ganzer Eintrag)

**Promotional text:**

```
Steer Audio Harbor on your Mac from the couch. Deck, Catalogue, and Settings — like on the Mac. Free.
```

**Description:**

```
Audio Harbor for iPhone and iPad is the remote for Audio Harbor on your Mac. The music plays on the Mac and its DAC — your iPhone or iPad steers.

You need Audio Harbor for Mac on the same network. Turn on Settings → Remote → Allow Remote Control on the Mac, then enter the six-digit code on the phone once. After that the phone reconnects on its own.

The remote uses the same three tabs as the Mac: Deck, Catalogue, and Settings.

What you can do
• Deck — transport, seek, and the Mac's listening stage; open the queue from the Deck; tap a playing song again to pause
• Catalogue — browse folders, albums, artists, and playlists, and search each like on the Mac
• Settings — change the Mac's Output, Sharing, and Directories (when both sides support it)
• Add songs to playlists and labels, or take them out — long-press a song, or use Playlist and Labels on the Deck
• Set the volume of your DAC — open the speaker on the Deck, or use the volume buttons. The DAC changes its own level, so the music stays bit-perfect.

What it is not
• Not a player on the iPhone or iPad. Nothing is copied to it.
• No account and no cloud. Phone and Mac talk directly over your local network.

The remote is free. Playback on the Mac follows the Mac app's trial and one-time unlock.
```

**Keywords:** `remote,mac,audiophile,DAC,volume,FLAC,DSD,bit-perfect,hi-res,player,control`

**Support URL:** `https://github.com/petergerov/audio-harbor/issues`
**Marketing URL:** Homepage (`docs/index.html`)
**Privacy Policy URL:** `https://petergerov.github.io/audio-harbor/privacy.html`

**Age rating:** 4+ (ganzer Eintrag) · **Copyright:** `2026 Gerov`

### What's New in This Version (1.1.0)

iOS 1.1.0 ist die **erste** iOS-Version — App Store Connect zeigt das Feld dafür nicht. Der Text ist für die Homepage, die Release-Notes und als Vorlage. Ab dem ersten iOS-Update gehört er ins Feld (pro Plattform eigener Text).

```
The first Audio Harbor for iPhone and iPad: a free remote for Audio Harbor on your Mac.

• Finds your Mac on the local network. Pair once with a six-digit code, and it reconnects on its own.
• Play, pause, skip, and seek. Browse folders, albums, artists, and playlists, search the whole catalogue, and jump anywhere in the queue.
• Set your DAC's volume with the slider or the volume buttons. The DAC changes its own level, so the music stays bit-perfect.
• On iPad, the same layout, centred, in any orientation.

The music plays on the Mac. Nothing is copied to your iPhone or iPad, and there is no account.
```

### What's New in This Version (1.1.1)

Das erste iOS-Update — hier zeigt App Store Connect das Feld. Die Description oben enthält die neuen Punkte schon (Playlists/Labels, Suche); für 1.1.0 ohne sie einreichen.

```
• Add a song to a playlist or take it out: long-press it and choose Add to Playlist. Labels work the same way. A checkmark shows where the song is, and you can make a new playlist or label right there.
• Playing a song or Play all keeps you in the list. The song that plays is marked.
• Search under Dirs, Albums, Artists, and Lists, like the catalogue search on the Mac: across every directory, or albums, artists, and playlists with a matching song.
• Dirs, Albums, Artists, and Lists stay at the top while you browse deeper. Tap one to go back to its start.
• Finds your Mac again more reliably after it restarts, and says so when it can't reach it.

Playlists, labels, and search need Audio Harbor 1.1.1 on your Mac.
```

### What's New — Deck · Catalogue · Settings (`develop`)

Copy for the next iOS update after 1.1.1 (bump marketing version when you cut the release). Needs the matching Mac build (remote protocol 3 for Settings).

```
The remote now matches the Mac.

• Bottom tabs: Deck, Catalogue, and Settings — the same three places as on the Mac.
• Deck shows the listening stage (Turntable or Reel-to-Reel), transport, and the queue from a button on the stage. No search on the Deck.
• Catalogue keeps browse and search under Dirs, Albums, Artists, and Lists.
• Settings edits the Mac: Output (device, modes or network radios, DSD as PCM), Sharing, Directories, and About. Add or remove folders still on the Mac.
• Tap a playing song again to pause; tap once more to resume (same on the Mac catalogue).
• Volume sits next to Queue on the Deck — tap the speaker to open the slider. The volume buttons still work. Live/Standby is the LED on the stage photo.
```

---

## 7. Screenshots

| Gerät | Größe (Portrait) | Pflicht |
|---|---|---|
| iPhone 6,9″ | 1320 × 2868 (oder 1290 × 2796) | Ja |
| iPad 13″ | 2064 × 2752 (oder 2048 × 2732) | Ja — das Target unterstützt iPad |

**iPhone** (Oktober 2026): [`marketing/app-store/iphone-1320x2868/`](marketing/app-store/iphone-1320x2868/), 5 Bilder, opak, 1320 × 2868:

1. **Deck** — „Your Mac plays. Your iPhone steers.“ (Deck-Stage, Transport, Volume/Queue in der Toolbar)
2. **Catalogue** — „Every album on your Mac, in your hand.“
3. **Queue** — „Jump anywhere in what plays next.“ (Queue-Sheet vom Deck)
4. **Nearby** — „Finds your Mac on its own. No account.“
5. **Pairing** — „Pair once with a code from the Mac.“

Die Daten sind erfunden (Künstler, Alben, generierte Cover — keine echte Musik, keine echten Gerätenamen). Sie kommen aus dem Fixture-Modus des Debug-Builds (`RemoteScreenshotFixture.swift`, Launch-Argument `-remoteScreenshot <scene>`), der im Release-Build nicht existiert. Texte stehen in `marketing/app-store/screenshots-iphone.txt`, die Rohaufnahmen in `raw-iphone/`. Neu erzeugen: `marketing/app-store/build-iphone.sh --capture` (baut, startet den Simulator „iPhone 17 Pro Max“, nimmt auf, setzt zusammen); ohne `--capture` nur neu zusammensetzen.

**iPad** (Oktober 2026): [`marketing/app-store/ipad-2064x2752/`](marketing/app-store/ipad-2064x2752/), 5 Bilder, opak, 2064 × 2752, gleicher Fixture-Modus auf dem Simulator „iPad Pro 13-inch (M5)“:

1. **Deck** — „Your Mac plays. Your iPad steers.“
2. **Catalogue** — „Every album on your Mac, in your hand.“
3. **Queue** — „Jump anywhere in what plays next.“
4. **Nearby** — „Finds your Mac on its own. No account.“
5. **Pairing** — „Pair once with a code from the Mac.“

Texte in `marketing/app-store/screenshots-ipad.txt`, Rohaufnahmen in `raw-ipad/`. Neu erzeugen: `marketing/app-store/build-ipad.sh --capture`; `compose-iphone.swift` setzt beide Formate zusammen.

App-Icon: kommt aus demselben Asset Catalog wie am Mac (1024er ohne Alphakanal).

---

## 8. Review notes (an Apple)

```
Audio Harbor for iPhone and iPad is the remote control for Audio Harbor for Mac, the same app record (Universal Purchase). It plays no audio itself.

To review:
1. Install the Mac build from this same submission on a Mac and add a folder with a few audio files.
2. On the Mac: Settings → Remote → turn on "Allow Remote Control", then "New Code".
3. On the iPhone or iPad (same Wi-Fi): allow local network access, tap the Mac, enter the six-digit code.
4. Use Deck, Catalogue, and Settings. Play, browse, search, open the queue from the Deck, and change the volume (speaker on the Deck or the device's volume buttons).

A screen recording of this flow is here: <URL>

Phone and Mac talk directly over the local network (Bonjour, TCP). There is no server, no account, and no data leaves the network.
```

- [ ] Bildschirmvideo des Ablaufs aufnehmen und als Link in die Notes (Review hat oft keinen Mac im selben Netz). Ohne Video droht die Rückfrage nach Guideline 2.1 bzw. 4.2.3 („App funktioniert nicht allein“).

---

## 9. App Privacy & Export Compliance

App Privacy gilt für beide Plattformen und bleibt **Data Not Collected**. Der Remote schickt Titel, Cover, Queue und Befehle nur zwischen eigenem iPhone und eigenem Mac im lokalen Netz; nichts davon erreicht uns. [`docs/privacy.html`](docs/privacy.html) beschreibt das im Abschnitt *iPhone remote and your local network*.

| Daten | Antwort |
|---|---|
| Tracking | Nein |
| Purchase History | Ja — Apple (StoreKit), nicht von uns an Dritte |
| Library-Daten über das Netz | Nur iPhone ↔ eigener Mac im lokalen Netz, nicht collected by developer |
| Diagnostics, Contact Info | Nein |

Export Compliance bleibt `NO`: Die Remote-Verbindung ist einfaches TCP mit Pairing-Token, ohne eigene Verschlüsselung.

---

## 10. Archive & Upload

```bash
git switch release/REL_1.1.0
xcodegen generate
# Xcode: Scheme AudioHarbor → Any iOS Device (arm64)
# Product → Archive (Release) → Distribute App → App Store Connect → Upload
# Danach dasselbe mit Destination Any Mac
```

- Nach Processing: iOS-Build der iOS-Version 1.1.0 zuweisen, Mac-Build der macOS-Version 1.1.0.
- „Missing Compliance“ sollte nicht erscheinen (`ITSAppUsesNonExemptEncryption = NO`).

---

## 11. Was Review beim Remote ablehnen könnte

- Hintergrund-Audio ohne Audio (Guideline 2.5.4) → `UIBackgroundModes` ist raus
- macOS-Entitlements im iOS-Build (ITMS-90046) → eigene iOS-Entitlements
- „App funktioniert nicht allein“ (Guideline 4.2.3) bzw. Reviewer kann nicht testen (2.1) → Review Notes mit Schritten + Bildschirmvideo
- Local-Network-Abfrage ohne verständlichen Text oder ohne Zustand nach *Ablehnen*
- iPad-Oberfläche, die nur ein hochskaliertes iPhone-Layout ist → mittig, max. 600 pt, alle Ausrichtungen
- Kauf-Hinweis mit hartcodiertem Preis statt `Product.displayPrice`
