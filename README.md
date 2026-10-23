# Clementine

App per Mac (menu bar) per convertire e modificare file trascinandoli. Tutto in locale, niente viene caricato online. Ispirata a Tangerine; codice scritto da zero con le API di macOS (ImageIO, PDFKit, AVFoundation).

- **Trascina un file + Shift** → menu rotondo di conversione (immagini, PDF, audio, video, documenti)
- **Trascina un file + Option** → menu rotondo con gli strumenti (Comprimi, Metadati, Ritaglia, Modifica testo, Aggiungi sfondo)
- Il risultato è salvato accanto all'originale, che non viene mai modificato.

## Installazione
La build gira su GitHub Actions: scarica `Clementine.zip` dagli artifact dell'ultima esecuzione (Actions → Build). L'app è firmata ad-hoc: al primo avvio clic destro → Apri.

In locale: `./scripts/package.sh` → `dist/Clementine.app`.

## Da fare
Annota, Redact, ritaglio libero, altri formati (WebP, MP3, GIF da video), più opzioni nei menu.
