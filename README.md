# iDown

Minimal iOS app that downloads files in the background.

- **Downloads tab:** paste a direct link and it downloads.
- **Browser tab:** open any page, tap the site's own download button, and iDown catches the file and saves it using the web view's own session (works with logins, one-time links, POST forms and blob links). These downloads are kept alive by the silent audio + location tricks rather than a system background download.

Background tricks used: background `URLSession`, silent looping audio, background location, Live Activity (Dynamic Island / lock screen).

Files are saved to Files → On My iPhone → iDown.

## Build

Push to `main` (or run the workflow manually). GitHub Actions builds an unsigned IPA: Actions → latest run → Artifacts → `iDown-unsigned-ipa`. Sideload it with Sideloadly / AltStore / etc.
