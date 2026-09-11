# Audio Harbor — Competitive notes

How to stay competitive with other audiophile players on macOS without becoming them.

Locked identity (see also [`PRODUCT.md`](PRODUCT.md)): local files, Shared as the everyday default, Exclusive + sample-rate match + DoP on Mac, AU / AUv3 on the Deck. Tagline: *Local. Bit-perfect. Calm.* Offer: free to install, 7-day trial, **€9.90** one-time unlock. No account, no subscription.

This is a strategy memo, not a feature backlog. Ship only what sharpens the identity.

---

## Who we actually compete with

| Player | What they win | Harbor does not copy |
|---|---|---|
| **Roon** | Metadata, discovery, multi-room, remote ecosystem | Server, AllMusic-style library, streaming tax |
| **HQPlayer** | Upsampling theatre, extreme DSP | 768 kHz marketing modes as the product |
| **Audirvāna Studio** | Local + Qobuz/Tidal, subscription | Streaming as the reason to exist |
| **Audirvāna Origin** | Local Exclusive / DoP on Mac, one-time license (~$150) plus paid Signal Processing Suite (~$90) | Their price, fragile Integer Mode branding, extra DSP SKU |
| **Pine Player Pro** | Format breadth, SACD ISO, CUE, converter, six DAC modes, MAS, ~$30 | Kitchen-sink UI, 768 kHz OSF as the story, dual-track default that is not bit-perfect |
| **Neutron / VOX** | Mobile hi-res, DSP toys | Crowded controls, Mac as afterthought |
| **Music.app / Swinsian** | Daily-driver Mac habits | Fake hi-res / no DSD Exclusive |

Two fights, not one. **Origin** is the prestige local player (~$150). **Pine** is the Mac App Store neighbor: same shopper, same “local DAC on a Mac” search, **$29.99** Pro (free Pine exists). Harbor does not win by matching Pine’s matrix. Harbor wins by being the calm, honest path at **€9.90**, with iPhone in the same product.

Roon wins metadata and multi-room. HQPlayer and Pine’s OSF win upsampling theatre. That is someone else’s cost structure. Harbor wins if the path to the DAC is trustworthy and the desk feels native.

---

## Pine Player

[`PRODUCT.md`](PRODUCT.md) already names the gap: Pine is powerful and crowded; Harbor ships less surface and a cleaner path from library to DAC. That is still the right frame. Pine is not a footnote.

### What Pine actually is

A long-lived MAS player (Siseong Ahn / digipine). Pro is **$29.99**. The free app already does a lot; Pro adds conversion, editing, and the heavier DAC modes.

It plays almost everything: FLAC, ALAC, APE, OGG, WMA, OPUS, DSD (DSF/DFF, DoP and PCM), **SACD ISO**, **CUE**, DTS / 5.1 / 7.1. It has a built-in **converter** (including SACD ISO → WAV/FLAC, PCM ↔ DSD, DST / `.dst`). Six **DAC Control Modes**: Priority (file rate, mixer bypass), Equalizer (required for the 12-band EQ), OSF / CSF (fixed-rate resampling, up to **32-bit / 768 kHz**), Multi Channel, AirPlay 2 multi-room. Internet radio, synced lyrics from the network, per-track gain/EQ, metadata editor.

Default playback is **dual audio tracks** so crossfade and on-the-fly format conversion work. Bit-perfect / gapless classical needs **single audio track**, which Pine still calls experimental and possibly unstable. That is the opposite of Harbor’s default: Shared is honest; Exclusive is bit-perfect when the rack is empty.

### Where Pine wins

- Format and collector files: CUE, APE, SACD ISO, DST, converter. Harbor is catching up on ISO/DFF; Pine has lived there for years.
- Shop visibility: MAS, “DAC / DSD / EQ / 768 kHz” in the subtitle. People searching that string land on Pine first.
- Price vs Origin: $30 feels cheap next to Audirvāna. Harbor is cheaper still (€9.90), but Pine **free** is the budget default.
- DSP as product: 12-band EQ, bass control, OSF/CSF. Audiophiles who *want* a processing playground pick Pine or HQPlayer.

### Where Harbor must not become Pine

Matching six DAC modes, 768 kHz OSF, a converter suite, internet radio, AirPlay 2, and dual-track-by-default is how Harbor dies. [`ARCHITECTURE.md`](ARCHITECTURE.md) already flags this: *scope creep (Pine clone)*. [`MARKETING.md`](MARKETING.md) says the same: no feature matrices that look like Pine.

Pine’s bit-perfect story is a mode buried under processing modes, and the bit-perfect track path is experimental. Harbor’s story is the reverse: **hear the file**; processing is an optional rack that *names* itself Shared · FX.

### Harbor’s angle against Pine

| Pine | Harbor |
|---|---|
| Everything on one screen, many DAC modes | Three surfaces: Library · Deck · Settings |
| Dual-track default; bit-perfect is experimental | Shared default; Exclusive / DoP when the DAC is ready |
| Built-in 12-band EQ as a DAC mode | AU / AUv3 you already own; empty rack stays bit-perfect |
| 768 kHz oversampling as a headline | No upsampling theatre |
| Mac only | Same catalogue language on iPhone / iPad; later Mac engine + phone remote |
| $29.99 Pro, or free with less | Free to install, 7 days, €9.90 once |
| Converter + DST encoder | Player, not a workshop (export/convert stays out of the main path) |

Steal Pine users who are tired of the kitchen sink, not Pine users who want a Swiss Army converter. Against Pine, CUE and ISO-as-album still matter — those are collector basics, not Pine-cloning. Do not race their encoder blog posts.

Success criterion already in [`PRODUCT.md`](PRODUCT.md): *UI feels simpler than Pine within the first session.* Keep that. Add: *the path label is understood in the first session.*

---

## Levers that matter

### 1. The signal path must be unimpeachable

In this niche people buy trust, not VU meters. Audirvāna regularly breaks on new macOS releases (Integer Mode, USB DACs). Harbor should be the player that **still plays after an OS update**.

- Visible path: Shared / Exclusive / DoP / Shared · FX — never imply bit-perfect over Bluetooth, AirPlay, or built-in speakers.
- Bit-perfect test files and short measurement notes on the site.
- CoreAudio treated as product, not backend: hog, rate match, DoP probe, honest PCM fallback.

Head-Fi / ASR: a loopback that is bit-perfect beats a feature matrix.

### 2. iPhone as remote, not a second library

Roon wins the listening chair. Audirvāna’s remote is weak. Harbor already has iOS.

- Mac is the engine on the DAC.
- iPhone steers queue, volume, album.
- Mode: *Remote to this Mac* — no account, no Roon-class server.

Largest product unlock that still fits the identity. [`PRODUCT.md`](PRODUCT.md) already lists this under Ecosystem; it should move forward once Exclusive is boringly reliable.

### 3. The AU rack is the DSP story

Audirvāna sells processing as an add-on. Harbor: use the plugins you already own (Sonarworks, FabFilter, Apple AU).

- Rack presets.
- One control to clear inserts and return to Exclusive.
- Convolution / headphone correction via AU, not a second HQPlayer.
- Loaded rack = Shared · FX. Empty rack = bit-perfect Exclusive / DoP.

Do not build a proprietary EQ suite to look “pro.”

### 4. Leave the collection as collectors have it

Roon dissolves folders into AllMusic. Pine already does CUE and SACD ISO. Harbor should be *clearer* than both at:

- Folder view, multi-disc sets, box sets
- CUE sheets
- SACD ISO per-track, DFF chapters
- Honest DST (list titles; don’t fake playback)

This is a real niche, not a checkbox. ISO / DFF work already started; finish it as *album objects*, not virtual-path trivia.

### 5. Daily driver, not a lab

Gapless, media keys, Now Playing, menu bar, keyboard, calm folder scan, ReplayGain (album). Audiophile apps often lose to Music.app in weekday use. Whoever does Exclusive **and** feels like a native Mac app steals Swinsian / Music users, not only Audirvāna users.

### 6. Price and Store as a weapon

Copy: *Free to install. Seven days. €9.90 once. No account.* Against Origin ~$150, Pine Pro $30, and Roon’s subscription. Pine’s **free** tier is the only cheaper neighbor — beat it on calm and honesty, not on format count.

MAS sandbox, Restore, and a quiet trial must be solid. In this market that offer is the sharpest position Harbor has — if playback after day 7 is gated cleanly and the engine holds up.

---

## Do not build to look competitive

These dilute *Local. Bit-perfect. Calm.* and drag Harbor into someone else’s cost structure:

- Qobuz / Tidal (or any streaming identity)
- Multi-room / AirPlay-as-product
- Roon-style metadata cloud
- Integer Mode as a marketing badge
- Upsampling to 768 kHz as theatre
- A second DSP product SKU next to Unlock

Optional streaming is listed as “later, if it doesn’t dilute” in [`PRODUCT.md`](PRODUCT.md). Default answer remains **no**.

---

## Next sharpening

If one thing moves first: **Mac as DAC engine + iPhone as remote**, plus hard bit-perfect proof.

Deck chrome (Turntable, Reel-to-Reel, Receiver) is character. Against Origin the comparison is price and trust. Against Pine it is *fewer modes, a default that is honest, AU instead of a 12-band DAC mode.* Both are decided on the path to the DAC and on weekday use at the desk.
