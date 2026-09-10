# Audio Harbor — App Store Submission (macOS first)

Erste Veröffentlichung: **Mac App Store only**. iPhone/iPad bleiben im Xcode-Projekt, gehen aber noch nicht live.

Stand der App im Repo (vor Store-Arbeit): Bundle `app.audioharbor.player`, Marketing-Version `0.1.0`, Entitlements leer, **kein StoreKit**. Unten steht, was vor dem Upload noch gebaut werden muss.

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
| Unlock-Preis | **9,90 €** (Deutschland / Euro-Storefront) |
| Abo | Nein — kein Auto-Renew, kein Account |

App Store Connect: **Pricing and Availability → Price Schedule → Free.** Die 9,90 € sitzen nur am IAP `unlock`, nicht an der App.

**Warum Non-Consumable, nicht Abo:** Audio Harbor ist lokal, ohne Login. 9,90 € ist ein Unlock, kein Mietzins. Apple hat für Non-Consumables **kein** offizielles „7-day introductory offer“ — die Trial-Uhr bauen wir selbst (StoreKit 2 + Keychain).

**Price-Tier:** In App Store Connect 9,90 € setzen. Falls die Storefront nur **9,99 €** als Standardstufe anbietet, 9,99 € nehmen und diese Datei anpassen — nicht 9,90 in der UI versprechen und 9,99 kassieren.

---

## 1. Vor dem ersten Archive — Blocker

Ohne diese Punkte Review oder Sandbox-Start nicht überstehen.

### 1.1 StoreKit (noch nicht im Code)

- [ ] StoreKit 2: Product laden, kaufen, `Transaction.currentEntitlements`, Finish, **Restore**
- [ ] Product ID: `app.audioharbor.player.unlock` (an ASC angleichen)
- [ ] Trial: Zeitstempel **erste Installation** im **Keychain** (überlebt Löschen der App auf demselben Mac besser als UserDefaults)
- [ ] Nach Tag 7 ohne Receipt: kein Playback; Catalogue / Settings / Restore bleiben erreichbar
- [ ] Paywall-Copy ehrlich: „7 days free. Then €9.90 once.“ inkl. Preis aus StoreKit (`displayPrice`), nicht hardcodiert
- [ ] StoreKit Configuration File für lokale Tests (`.storekit`)
- [ ] Sandbox-Apple-ID: Trial ablaufen lassen, kaufen, App löschen, Restore

Gate nach Ablauf (Vorschlag, nicht verhandelbar für Review):

| Oberfläche | Ohne Unlock nach 7 Tagen |
|---|---|
| Catalogue, Suche, Ordner, Playlists ansehen | Ja |
| Play / Exclusive / DoP / Rack | Nein — Unlock-Sheet |
| Restore Purchases | Immer |

Während der 7 Tage: volle App, kein Wasserzeichen, kein Nagscreen alle 30 Sekunden. Ein ruhiger Hinweis in Settings („Trial · n days left“) reicht.

### 1.2 Mac App Store Sandbox

`AudioHarbor/Resources/AudioHarbor.entitlements` ist heute leer. MAS **erzwingt** App Sandbox.

Mindestens:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-only</key>
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

### 1.3 Version, Signing, Privacy-URL

- [ ] Marketing-Version auf **1.0.0** (Build `1` oder höher, jeder Upload +1)
- [ ] Team: Apple Developer Program, Signing **Apple Distribution** / Mac App Store (nicht Developer ID)
- [ ] Privacy Policy **öffentlich per HTTPS** — Entwurf: [`docs/privacy.html`](docs/privacy.html). GitHub Pages oder gerov-Domain. App Store Connect braucht eine URL, kein `file://`
- [ ] In der Policy einen Satz zum Kauf ergänzen: Receipt bleibt bei Apple; wir speichern keinen Account

### 1.4 App Store Connect (Verträge)

- [ ] Paid Applications Agreement akzeptieren
- [ ] Bank / Tax / W-8 oder EU-Steuer
- [ ] Paid Apps + IAP sind erst buchbar, wenn der Vertrag **Active** ist (sonst „Missing Metadata“ am Produkt)

---

## 2. App Store Connect — App anlegen (nur Mac)

1. [App Store Connect](https://appstoreconnect.apple.com) → My Apps → **+** → New App
2. Platforms: **nur macOS** (iOS nicht ankreuzen)
3. Name: **Audio Harbor**
4. Primary language: **English (U.S.)**
5. Bundle ID: `app.audioharbor.player` (in Developer Portal anlegen, falls fehlend)
6. SKU: `audio-harbor-mac`
7. User Access: Full Access
8. **Pricing and Availability:** Price = **Free**. Availability = die Länder, in denen ihr listen wollt. Nicht versehentlich 9,90 € als App-Preis setzen.

Später iPhone/iPad: dieselbe App um die Plattform **iOS** erweitern, nicht eine zweite App (außer Apple/Bundle zwingt uns). IAP `unlock` dann für beide Plattformen freigeben — ein Kauf, alle Geräte desselben Apple-ID.

---

## 3. In-App Purchase anlegen

App → Monetization → In-App Purchases → **Non-Consumable**

| Feld | Wert |
|---|---|
| Reference Name | Audio Harbor Unlock |
| Product ID | `app.audioharbor.player.unlock` |
| Price | 9,90 € (DE); übrige Storefronts von Apple ableiten lassen |
| Availability | Alle Länder, in denen wir listen |

**Localization (EN, Pflicht):**

- Display Name: `Unlock Audio Harbor`
- Description: `One-time unlock after the 7-day trial. Play your local library — Exclusive, DoP, and the plugin rack included.`

**Localization (DE, empfohlen):**

- Anzeigename: `Audio Harbor freischalten`
- Beschreibung: `Einmaliger Kauf nach 7 Tagen Probe. Lokale Bibliothek spielen — inklusive Exclusive, DoP und Plugin-Rack.`

Review screenshot: Paywall mit Preis und Restore. Review notes: Sandbox-Schritte (Trial umgehen per StoreKit-Config oder Hinweis, wie Reviewer 7 Tage überspringt — z. B. Debug-Override nur in `#if DEBUG`, nicht im Release).

---

## 4. Listing-Copy (English — so paste)

**Name:** Audio Harbor  
**Subtitle:** Local audiophile player  
**Category:** Music  
**Secondary:** Entertainment (optional)

**Promotional text** (up to 170):

```
Free to install. Seven days full use, then €9.90 once — no subscription. Local folders, bit-perfect Exclusive and DoP on Mac, AU and AUv3 on the Deck. No account.
```

**Description:**

```
Audio Harbor is a local audiophile player for Mac. Add the folders you already have. Browse a quiet catalogue. Hear the file.

Free to install for everyone. Seven days full use after you first install. Then a one-time unlock (€9.90). No subscription. No account.

Shared is the everyday path — other Mac sound still works. Exclusive takes over a USB DAC for bit-perfect playback and sample-rate match. DoP sends DSD to a DAC that understands it; otherwise Audio Harbor converts to PCM so the track still plays.

AUv3 inserts (and classic AU on Mac) live on the Deck rack. The rack uses Shared. Exclusive stays bit-perfect when the rack is empty.

What you get
• Folders you pick — security-scoped, remembered
• Catalogue by album, artist, and folder, with search and playlists
• FLAC, ALAC, WAV, AIFF, AAC, MP3, DSF, DFF
• SACD ISO — stereo tracks listed from the disc TOC
• Shared, Exclusive, and DoP — explained in plain language
• Optional AU / AUv3 rack on Shared

What you do not get
• Streaming services or an account
• Bit-perfect over Bluetooth, AirPlay, or built-in speakers (those stay Shared)
• A kitchen-sink mixer

Privacy: nothing about your library leaves the Mac. See the Privacy Policy.

Restore Purchases is in Settings if you reinstall or switch Macs with the same Apple ID.
```

**Keywords** (100 characters, comma-separated, no spaces after commas if you need the room):

```
audiophile,FLAC,DSD,DoP,bit-perfect,DAC,local,player,AUv3,ALAC,SACD,hi-res
```

**Support URL:** `https://github.com/petergerov/audio-harbor/issues` (oder eine Support-Seite auf der Marketing-Domain)  
**Marketing URL:** Homepage (`docs/index.html` muss live HTTPS sein)  
**Privacy Policy URL:** live `privacy.html`

**Age rating:** 4+ — keine user-generated chats, keine Werbung, keine unrestricted web.

**Copyright:** `2026 Gerov`

---

## 5. Screenshots (Mac)

App Store Connect verlangt mindestens **einen** Satz. Sinnvoll:

| Größe | Typisches Display |
|---|---|
| 1280 × 800 | 13″ / 16:10 |
| 2560 × 1600 | Retina 13″ |

Mindestens 3, besser 5 Bilder, **ohne** Fake-Hardware-Rahmen:

1. Catalogue (Alben, ruhig)
2. Deck / Now Playing + VU
3. Settings — Shared / Exclusive / DoP erklärt
4. Plugin-Rack (Shared · FX)
5. Paywall oder Settings mit Trial/Unlock — Reviewer sieht das Angebot

Caption-Stil: ein Satz, Englisch, kein „Best ever!!!“.

App-Icon: Asset Catalog ist vollständig (1024 + Mac-Größen). MAS-Icon ohne Transparenz-Probleme im 1024er.

---

## 6. Review notes (an Apple)

```
Audio Harbor plays local audio files the user adds via a folder picker.

Trial: 7 days from first launch (Keychain). After that, playback requires the non-consumable IAP “Unlock Audio Harbor” (€9.90). Restore Purchases is in Settings.

To review past the trial immediately: use the sandbox account; or in the attached StoreKit notes, purchase the unlock. There is no demo login — there are no accounts.

Exclusive / DoP need an external USB DAC. Shared works on built-in speakers.

SACD ISO: stereo TOC tracks. DST-compressed tracks list titles but do not play yet.
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

- Destination **macOS**, nicht iOS
- Destination iOS im Target darf bleiben; einfach nicht archivieren
- Nach Processing: Build der Version 1.0.0 zuweisen, IAP der Version anhängen (IAP muss **Ready to Submit** sein)
- Export Compliance: ohne eigenen Verschlüsselungs-Layer außer HTTPS → übliche ITSAppUsesNonExemptEncryption = NO, wenn ihr nichts Eigenes verschlüsselt

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

- [ ] Homepage-CTA von GitHub auf Mac App Store umbiegen (`docs/index.html`, `docs/MARKETING.md`)
- [ ] Privacy-URL und Support-URL final
- [ ] Phased Release optional
- [ ] iOS/iPadOS: eigene Screenshots + dieselbe IAP-ID, wenn die Plattform ergänzt wird. Trial-Uhr **pro Gerät** (erste Installation); Unlock folgt der Apple-ID via Restore

---

## Identität (Ist-Stand Xcode)

| | |
|---|---|
| Display name | Audio Harbor |
| Bundle ID | `app.audioharbor.player` |
| Category (Info.plist) | `public.app-category.music` |
| macOS deployment | 14.0 |
| App-Preis | Free — jeder darf installieren |
| IAP product (geplant) | `app.audioharbor.player.unlock` |
| Trial | 7 Tage ab erster Installation |
| Unlock | 9,90 € einmalig |
