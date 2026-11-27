# iDown

Minimal iOS app that downloads files in the background.

- **Downloads tab:** paste a direct link and it downloads.
- **Browser tab:** open any page, tap the site's own download button, and iDown catches the file and downloads it in the background (cookies, referer and user agent are passed along).

Background tricks used: background `URLSession`, silent looping audio, background location, Live Activity (Dynamic Island / lock screen).

Files are saved to Files → On My iPhone → iDown.

## Build

Push to `main` (or run the workflow manually). GitHub Actions builds an unsigned IPA: Actions → latest run → Artifacts → `iDown-unsigned-ipa`. Sideload it with Sideloadly / AltStore / etc.
