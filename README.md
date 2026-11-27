# BG Downloader

Minimal iOS app: paste a link, it downloads the file in the background.

Background tricks used: background `URLSession`, silent looping audio, background location, Live Activity (Dynamic Island / lock screen).

Files are saved to Files → On My iPhone → BG Downloader.

## Build

Push to `main` (or run the workflow manually). GitHub Actions builds an unsigned IPA: Actions → latest run → Artifacts → `BGDownloader-unsigned-ipa`. Sideload it with Sideloadly / AltStore / etc.
