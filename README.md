# Resonance for iOS

A local-files music player for iPhone, designed in the spirit of Material 3 / Material You.
It is the iOS sibling of [Resonance for Android](https://github.com/xenone-beta/Resonance).
No accounts, no ads, no network access: it plays the music you copy onto your phone.

> Status: first version. It is built from source by GitHub Actions and has not been tested on a lot of devices yet. Please open an issue if something breaks.

## Features

- Library from the app's folder in the **Files** app, with tags and covers (MP3, M4A/AAC, FLAC, WAV, AIFF, CAF)
- Songs, albums, artists, playlists, favorites, search
- Full-screen player
  - covers sit on a **strip**: drag sideways and the next or previous cover slides in under your finger
  - drag down to close, double-tap the sides for ±10 s, tap for the spectrum ring
  - **play/pause** button that morphs between its two states
  - **gradient** background from the cover colors
  - wavy progress bar
- 10-band **equalizer**, playback **speed** and **pitch**
- **Sleep timer**, synced **lyrics** (`.lrc` file next to the song)
- Lock screen and Control Center controls, headphone buttons
- **Your own accent color**: pick it on a palette or type a HEX code
- Languages: English, Russian (or follow the system)
- Light, dark and black (AMOLED) themes

## Install (AltStore / Sideloadly)

1. Open the **Actions** tab (or **Releases**) of this repository and download `Resonance.ipa`.
2. Install it with [AltStore](https://altstore.io) (My Apps → **+** → pick the IPA) or Sideloadly.
   The IPA is unsigned on purpose: your Apple ID signs it during installation.
3. With a free Apple ID the app has to be refreshed every 7 days (AltStore does it in the background).

## Add music

Copy your songs into **Files → On My iPhone → Resonance**, then open the app and pull down on *Songs*,
or tap **+** to import files or folders. Put `cover.jpg` in an album folder if the files have no embedded art.
Lyrics: put `Song name.lrc` next to `Song name.mp3`.

## Build

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen), so there is no `.xcodeproj` in the repo.
GitHub Actions builds on every push (`.github/workflows/build.yml`). To build on a Mac:

```sh
brew install xcodegen
xcodegen generate
open Resonance.xcodeproj
```

Push a tag such as `v1.0.0` to publish a release with the IPA.

## Differences from the Android version

- No Material You wallpaper colors on iOS: the app uses your accent color, or colors from the cover.
- Music is read from the app's own folder; the system Music library (Apple Music) is not used.
- Statistics, widget and Android-only tools are not ported yet.

## Русский

Локальный музыкальный плеер для iPhone в стиле Material You. Музыку нужно скопировать в папку
**Файлы → На iPhone → Resonance**. Установка: скачайте `Resonance.ipa` из Actions или Releases и
поставьте через AltStore (подпись выполняется вашим Apple ID, раз в 7 дней приложение нужно обновлять).

## License

MIT
