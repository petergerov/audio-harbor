# Pegeltest DSD (DoP) gegen PCM

Zwei Testdateien, beide 30 s, 1 kHz Sinus, Stereo, gleich laut nach Norm:

| Datei | Inhalt |
|---|---|
| `Level test PCM 44k1 24bit 1kHz -6dBFS.flac` | PCM, 44,1 kHz / 24 Bit, −6 dBFS |
| `Level test PCM 88k2 24bit 1kHz -6dBFS.flac` | dasselbe mit 88,2 kHz, der Rate von DSD als PCM: zeigt, ob der DAC je nach Rate anders laut spielt |
| `Level test DSD64 1kHz -6dB SACD.dsf` | DSD64, −6 dB nach SACD-Norm (25 % Aussteuerung) |

−6 dB statt 0 dB schont Lautsprecher und Ohren. Der Abstand zwischen DSD und PCM ist derselbe.

Geprüft mit dem Decoder der App: FLAC −6,00 dBFS; DSF als PCM bei *DSD as PCM* 0 dB −12,01 dBFS,
bei +6 dB −6,01 dBFS. Mit +6 dB sind beide also gleich laut.

## Messen

**Vorher die Lautstärke am Verstärker weit herunterdrehen.** Ein Sinuston ist lauter, als er klingt.

1. Lautstärke am DAC einmal einstellen und während des ganzen Tests nicht mehr ändern.
2. Output **Exclusive**: die FLAC-Datei spielen und den Pegel ablesen.
3. Output **DoP**: die DSF-Datei spielen und den Pegel ablesen.
4. Gegenprobe: Output **Exclusive**, *DSD as PCM* **+6 dB**, die DSF-Datei spielen. Das muss gleich laut sein wie Schritt 2.

**Messgerät:**

- **Multimeter**, AC-Spannung, am Line-Ausgang (Cinch) des DAC: dB = 20 · log10(U_DoP / U_PCM).
  1 kHz liegt im Messbereich jedes Multimeters.
- **Schallpegel-App** auf dem Handy, Handy fest an derselben Stelle vor dem Lautsprecher:
  die Differenz der beiden Werte in dB direkt ablesen.

**Ergebnis:** Der Unterschied zwischen Schritt 3 und Schritt 2 ist der Pegel, den der DAC bei DSD
zusätzlich draufgibt. 0 dB heißt, der DAC hält sich an die Norm.
