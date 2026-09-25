# Audio Harbor — Competitive notes

How to stay competitive with other audiophile players on macOS without becoming them.

Locked identity (see also [`PRODUCT.md`](../docs/PRODUCT.md)): local files, Shared as the everyday default, Exclusive + sample-rate match + DoP on Mac, AU / AUv3 on the Deck. Tagline: *Local. Bit-perfect. Calm.* Offer: free to install, 7-day trial, **€9.90** one-time unlock. No account, no subscription.

This is a strategy memo, not a feature backlog. Ship only what sharpens the identity.

Contents: who we compete with · prices and our price · Pine Player · EQ, effects and DSD · levers · what not to build · sources.

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

Two fights, not one. **Origin** is the prestige local player (~$150). **Pine** is the Mac App Store neighbor: same shopper, same “local DAC on a Mac” search, **$29.99** Pro (free Pine exists). Harbor does not win by matching Pine’s matrix. Harbor wins by being the calm, honest path at **€9.90** at launch (then €14.99, then €19.99), with iPhone in the same product.

Roon wins metadata and multi-room. HQPlayer and Pine’s OSF win upsampling theatre. That is someone else’s cost structure. Harbor wins if the path to the DAC is trustworthy and the desk feels native.

---

## Prices

As of **25 September 2026**. Prices from the US Mac App Store or the vendor sites unless given in €. Check again before any price change.

| App | Price | Model | Relevance |
|---|---|---|---|
| **Pine Player Pro** | **$29.99** | Paid app, no trial | DoP, SACD ISO, Exclusive — direct model and main rival |
| Pine Player | Free | — | Lite version |
| **Colibri** | **$19.99** | Paid app | Bit-perfect, Exclusive / hog; DSD not checked |
| **Fidelia** | Free + 14-day trial → **$99.99** (+ $49.99 Network & Server) | Non-consumable unlock | Exclusive, DoP — same model as ours, much pricier |
| Vox | Free, Premium from $4.99/month | Subscription | Mainstream |
| Swinsian | $34.95 | One-time, outside the MAS | Library manager |
| BitMuse | $99.95 | One-time | Exclusive, DoP |
| **Audirvāna Origin** | **€149.99** | One-time | Full feature set |
| Audirvāna Studio | €7.99/month · €79.99/year (since 6 Jan 2026) | Subscription | With streaming |
| **Roon** | $14.99/month · $829.99 lifetime | Subscription / lifetime | Multi-room, server |

No app showed rating counts on the US store pages (“not enough ratings”) — the niche is small.

### Reading the prices

- Lean players sit at **$20–30**; the big names at **$100–150** or on subscription.
- Pine Player Pro costs $29.99 with no trial. Harbor offers DoP, SACD ISO including DST, the AU rack, a calmer UI, and a trial — no reason to sit at a third of that.
- Fidelia proves that free + trial + one-time unlock works in this audience, even at $99.99.
- One-time, no subscription, no account is the argument against Audirvāna Studio and Roon.
- The audience (external DAC, DSD, SACD ISO) is not very price-sensitive; a low price reads as “toy.”

### Price plan

| Phase | Price |
|---|---|
| Launch (first weeks) | **€9.90** — announced as a launch price, for first users and reviews |
| After launch | **€14.99** |
| Regular, once reviews are in or iPhone / iPad ships | **€19.99** — Colibri level, clearly under Pine Player Pro |
| Later, if iPhone / iPad is one purchase for all devices | Consider **€24.99–29.99** |

Each step up is announced ahead (“launch price until …”) so early buyers feel rewarded, not undercut.

The model stays: free app, trial, non-consumable `com.gerov.audioharbor.unlock`, no subscription. Consider moving the trial from 7 to **14 days** (Fidelia level; audiophiles test with several DACs).

[`APP_STORE_SUBMISSION.md`](../APP_STORE_SUBMISSION.md), the homepage, and the offer lines in this memo say **€9.90** — right for launch; mark it as a launch price there. At each step, update the promotional text, description, IAP section, homepage, and review screenshot. The app itself shows `displayPrice` from StoreKit.

---

## Pine Player

[`PRODUCT.md`](../docs/PRODUCT.md) already names the gap: Pine is powerful and crowded; Harbor ships less surface and a cleaner path from library to DAC. That is still the right frame. Pine is not a footnote.

### What Pine actually is

A long-lived MAS player (Siseong Ahn / digipine). Pro is **$29.99**. The free app already does a lot; Pro adds conversion, editing, and the heavier DAC modes.

It plays almost everything: FLAC, ALAC, APE, OGG, WMA, OPUS, DSD (DSF/DFF, DoP and PCM), **SACD ISO**, **CUE**, DTS / 5.1 / 7.1. It has a built-in **converter** (including SACD ISO → WAV/FLAC, PCM ↔ DSD, DST / `.dst`). Six **DAC Control Modes**: Priority (file rate, mixer bypass), Equalizer (required for the 12-band EQ), OSF / CSF (fixed-rate resampling, up to **32-bit / 768 kHz**), Multi Channel, AirPlay 2 multi-room. Internet radio, synced lyrics from the network, per-track gain/EQ, metadata editor.

Default playback is **dual audio tracks** so crossfade and on-the-fly format conversion work. Bit-perfect / gapless classical needs **single audio track**, which Pine still calls experimental and possibly unstable. That is the opposite of Harbor’s default: Shared is honest; Exclusive is bit-perfect when the rack is empty, and stays exclusive (Exclusive · FX) when it is not.

### Where Pine wins

- Format and collector files: CUE, APE, SACD ISO, DST, converter. Harbor now plays SACD ISO (including DST) and DFF chapters; Pine still has the converter and `.dst` container.
- Shop visibility: MAS, “DAC / DSD / EQ / 768 kHz” in the subtitle. People searching that string land on Pine first.
- Price vs Origin: $30 feels cheap next to Audirvāna. Harbor is cheaper still (€9.90), but Pine **free** is the budget default.
- DSP as product: 12-band EQ, bass control, OSF/CSF. Audiophiles who *want* a processing playground pick Pine or HQPlayer.

### Where Harbor must not become Pine

Matching six DAC modes, 768 kHz OSF, a converter suite, internet radio, AirPlay 2, and dual-track-by-default is how Harbor dies. [`ARCHITECTURE.md`](../docs/ARCHITECTURE.md) already flags this: *scope creep (Pine clone)*. [`MARKETING.md`](MARKETING.md) says the same: no feature matrices that look like Pine.

Pine’s bit-perfect story is a mode buried under processing modes, and the bit-perfect track path is experimental. Harbor’s story is the reverse: **hear the file**; processing is an optional rack that *names* itself Exclusive · FX or Shared · FX.

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

Success criterion already in [`PRODUCT.md`](../docs/PRODUCT.md): *UI feels simpler than Pine within the first session.* Keep that. Add: *the path label is understood in the first session.*

---

## EQ, effects and DSD

> Compiled from general knowledge, **not checked against the current manuals**. Verify per app before using it in marketing or comparisons.

### Why DSP always means PCM

DSD is a 1-bit stream at 2.8 MHz and up; the information is in the pulse density, not in sample values. EQ, convolution, even a volume change need real sample values. So every player works the same way:

```
PCM file ─────────────────┐
                          ├─► float PCM (32/64-bit) ─► EQ / FX / volume ─► dither ─► 24/32-bit PCM ─► DAC
DSD file ─► DSD→PCM ──────┘                                                       └─► (optional) PCM→DSD modulator ─► DoP/native DSD ─► DAC
```

As soon as DSP is active, playback is **no longer bit-perfect** — in exclusive mode too. The DAC gets clean PCM at a fixed rate, but not the original bits.

### How the competition does it

| App | EQ / effects | DSD with DSP active | Output with DSP |
|---|---|---|---|
| **Pine Player Pro** | Built-in 12-band EQ, per-track EQ | → PCM | EQ only in the “Equalizer” DAC mode; “Priority” (bit-perfect) turns the EQ off |
| **Audirvāna** | AU plugins, upsampling (SoX / r8brain), own paid DSP suite | → PCM | Stays exclusive (hog / Integer Mode) with DSP |
| **Roon** | Parametric EQ, convolution, crossfeed, headroom, sample-rate conversion | → PCM, optionally back to DSD | PCM, or DSD re-made by its own modulator |
| **Fidelia** | AU plugins, upsampling | → PCM | Stays exclusive (hog) with DSP |
| **HQPlayer** (reference) | Filters, convolution, EQ | → PCM | Speciality: PCM→DSD modulation, e.g. DSD256 from any source |
| **Vox, Swinsian** | Simple EQ | Vox → PCM; Swinsian little DSD | Through the system mixer, not bit-perfect |
| **Colibri** | Little or nothing — the selling point is bit-perfect | — | — |

### What the DAC sees

- **PCM + DSP, exclusive:** the app holds the DAC and sets the rate (file or upsampling rate). The DAC gets processed 24/32-bit PCM; no mixer, no macOS resampling — but changed samples.
- **PCM + DSP, shared:** the same processing, then the macOS mixer and possibly its resampler on top.
- **DSD re-made (Roon, HQPlayer):** the DAC gets DoP / native DSD again and shows “DSD” — but a newly modulated stream, not the original bits. Quality depends on the modulator; good ones need a lot of CPU.
- **Volume:** digital volume is DSP too. Serious players add headroom and dither — or leave volume to the DAC, as Harbor does in Exclusive.

### Where Harbor stands

- Harbor follows the industry rule: rack active → PCM, not bit-perfect.
- **Shipped: Exclusive · FX.** With plugins and Exclusive / DoP on an external DAC, Harbor holds the DAC (hog) at the file’s rate and the plugin graph plays straight into it: no system mixer, no macOS resampling. On par with Audirvāna / Fidelia. Open: our own dither to 24-bit (today the HAL converts float to integer). Without a DAC or in Shared mode: Shared · FX.
- **Not pursuing: DSD re-modulation after DSP** (like Roon / HQPlayer) — a big project, the value is in the modulator, and it does not fit the simple product story.

---

## Levers that matter

### 1. The signal path must be unimpeachable

In this niche people buy trust, not VU meters. Audirvāna regularly breaks on new macOS releases (Integer Mode, USB DACs). Harbor should be the player that **still plays after an OS update**.

- Visible path: Shared / Exclusive / DoP / Exclusive · FX / Shared · FX — never imply bit-perfect over Bluetooth, AirPlay, or built-in speakers.
- Bit-perfect test files and short measurement notes on the site.
- CoreAudio treated as product, not backend: hog, rate match, DoP probe, honest PCM fallback.

Head-Fi / ASR: a loopback that is bit-perfect beats a feature matrix.

### 2. iPhone as remote, not a second library

Roon wins the listening chair. Audirvāna’s remote is weak. Harbor already has iOS.

- Mac is the engine on the DAC.
- iPhone steers queue, volume, album.
- Mode: *Remote to this Mac* — no account, no Roon-class server.

Largest product unlock that still fits the identity. [`PRODUCT.md`](../docs/PRODUCT.md) already lists this under Ecosystem; it should move forward once Exclusive is boringly reliable.

### 3. The AU rack is the DSP story

Audirvāna sells processing as an add-on. Harbor: use the plugins you already own (Sonarworks, FabFilter, Apple AU).

- Rack presets.
- One control to clear inserts and return to Exclusive.
- Convolution / headphone correction via AU, not a second HQPlayer.
- Loaded rack = Exclusive · FX on a DAC (Shared · FX otherwise). Empty rack = bit-perfect Exclusive / DoP.

Do not build a proprietary EQ suite to look “pro.” There is no bit-perfect EQ — see below.

### There is no bit-perfect EQ

**Bit-perfect** means the samples that leave the Mac are the same bits as the file (or DoP: the same DSD bits, packed). Any EQ that actually equalizes multiplies the signal by a filter. After that the numbers are different. That is not a bug. That *is* EQ.

What other players sometimes call a “bit-perfect EQ” is something else:

- **Exclusive + EQ, no resampling.** The DAC gets the *processed* rate; the system mixer stays out. The transport is clean. The payload is no longer the file.
- **EQ at zero / bypass.** The path can stay bit-perfect. That is a switched-off EQ, not an EQ.
- **EQ after the DAC** (analog, or hardware on the device). Digital stays bit-perfect; correction happens in analog.

What *does* exist is an **honest, high-quality EQ**: native sample rate, 64-bit float, linear-phase FIR or a well-set IIR, dither when returning to 24/32-bit. It can sound invisible. It is still not bit-perfect to the file.

Harbor’s model stays: empty rack = Exclusive / DoP = the file. Loaded AU = **Exclusive · FX** (or **Shared · FX** without a DAC) — a clean transport, a processed payload — and the path says so. A “Bit-Perfect EQ” switch would be Pine-style marketing. Correction without touching the file: AU on the rack (Sonarworks, headphone FIR) or analog after the DAC — not an EQ that pretends the bits are untouched.

### 4. Leave the collection as collectors have it

Roon dissolves folders into AllMusic. Pine already does CUE and SACD ISO. Harbor should be *clearer* than both at:

- Folder view, multi-disc sets, box sets
- CUE sheets (still to ship)
- SACD ISO per-track, including DST decode to the same DoP / PCM path
- DFF chapters and DST-compressed DFF

This is a real niche, not a checkbox. ISO / DFF / DST playback is in; the next honesty step is treating a disc as an album object, not only virtual paths.

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
- A “bit-perfect EQ” (impossible if the EQ changes the signal)
- Upsampling to 768 kHz as theatre
- A second DSP product SKU next to Unlock

Optional streaming is listed as “later, if it doesn’t dilute” in [`PRODUCT.md`](../docs/PRODUCT.md). Default answer remains **no**.

---

## Next sharpening

If one thing moves first: **Mac as DAC engine + iPhone as remote**, plus hard bit-perfect proof.

Deck chrome (Turntable, Reel-to-Reel, Receiver) is character. Against Origin the comparison is price and trust. Against Pine it is *fewer modes, a default that is honest, AU instead of a 12-band DAC mode.* Both are decided on the path to the DAC and on weekday use at the desk.

---

## Sources

- [Pine Player Pro — App Store](https://apps.apple.com/us/app/pine-player-pro/id6474128342?mt=12)
- [Pine Player — App Store](https://apps.apple.com/us/app/pine-player/id1112075769?mt=12)
- [Fidelia — App Store](https://apps.apple.com/us/app/fidelia-audiophile-player/id416135376?mt=12)
- [Colibri — App Store](https://apps.apple.com/us/app/colibri/id1178295426?mt=12)
- [Audirvāna prices](https://audirvana.com/price/)
- [Roon pricing](https://roon.app/en/pricing)
- [BitMuse: Mac player comparison 2026](https://bitmuse.app/best-music-player-mac)
- [FileMinutes: Best Audio Players for macOS](https://www.fileminutes.com/blog/best-audio-players-for-macos-2025/)
