# App Review Response — Audio Harbor 1.0.0 (7)

Antwort auf Submission `bf8f2b4e-e84a-4bca-8205-90549435bbd2` (Review vom 23.09.2026, Guideline 2.1(b) und 4).

## Vor dem Absenden

- [ ] Business → Agreements: **Paid Applications Agreement** ist **Active** (Bank + Steuer vollständig)
- [ ] IAP `com.gerov.audioharbor.unlock`: Status **Ready to Submit** (nicht „Missing Metadata“), Preis, Lokalisierung, Review-Screenshot gesetzt
- [ ] IAP ist auf der Seite von Version 1.0.0 unter „In-App Purchases and Subscriptions“ **angehängt**
- [ ] Build 7 archiviert, hochgeladen und der Version zugewiesen
- [ ] In TestFlight mit Sandbox-Account getestet: Kauf, Restore, Fenster schließen und über Window → Audio Harbor (⌘0) wieder öffnen
- [ ] Zeilen in `[eckigen Klammern]` unten nur stehen lassen, wenn der Punkt wirklich erledigt ist; Klammern vor dem Absenden entfernen

## Nachricht an App Review

```
Hello,

Thank you for the review and the detailed feedback. We have addressed both issues in build 1.0.0 (7).

Guideline 2.1(b) – In-App Purchase "unlock" unavailable

The unlock could not be loaded because the app requested a product identifier that did not
match the one configured in App Store Connect. The app now requests the correct identifier,
com.gerov.audioharbor.unlock (non-consumable, "Unlock Audio Harbor").
[- The In-App Purchase is complete and attached to this version.]

We also improved the app itself: the unlock button now shows the localized App Store
price only once the product has loaded, and the app retries loading the product when the
unlock screen is opened.

How to test the purchase:
1. Launch Audio Harbor and open Settings → License.
2. Click "Unlock · <price>" and complete the purchase with the sandbox account.
3. The status changes to "Unlocked". "Restore Purchase" is available on the same screen.

The 7-day trial starts on first launch, so playback works during review without a purchase.
The unlock screen and the purchase flow are available at any time in Settings → License.

Guideline 4 – Design

The main window is now listed in the Window menu ("Window → Audio Harbor", shortcut ⌘0),
so it can be reopened after it has been closed. Playback continues while the window is closed.

Thank you,
Petar Gerov
```
