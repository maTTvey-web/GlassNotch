# GlassNotch

A Dynamic Island-style notch for macOS, built with Swift and SwiftUI.

GlassNotch puts music controls, calendar events and small everyday tools in a compact interface at the top of your screen.

## Download

**For macOS 14 Sonoma or later.**

1. Open [**Latest Release**](https://github.com/maTTvey-web/GlassNotch/releases/latest).
2. Download `GlassNotch.dmg` from the release assets.
3. Open the DMG and drag `GlassNotch` to `Applications`.
4. Launch GlassNotch.

If there is no DMG attached to the latest release yet, check the [Releases page](https://github.com/maTTvey-web/GlassNotch/releases) for available builds.

If macOS blocks the app, try right-clicking it and choosing **Open**. Only use Terminal's `xattr` command if you trust the build and understand what it does:

```bash
xattr -cr /Applications/GlassNotch.app
```

## Preview

<!-- Add real project screenshots to the assets folder using these filenames. -->
<p align="center">
  <img src="assets/overview.png" alt="GlassNotch interface overview" width="100%">
</p>

<p align="center">
  <img src="assets/music.png" alt="Music controls" width="49%">
  <img src="assets/calendar.png" alt="Calendar events" width="49%">
</p>

<p align="center">
  <img src="assets/tools.png" alt="Quick tools" width="49%">
  <img src="assets/settings.png" alt="Settings" width="49%">
</p>

## Features

### Music controls

- Control Spotify and Apple Music playback.
- View the current track, artist and playback progress.
- Show track artwork when available.
- Read media information from supported browsers and websites.

Browser media support includes Safari, Google Chrome, Brave, Microsoft Edge and Arc. It depends on the browser and the media session exposed by the website.

### Calendar

- View today's calendar events.
- Access meeting links when they are included in an event.

### Quick tools

- **Focus timer** — a Pomodoro-style timer.
- **Quick notes** — keep short notes close by.
- **Clock** — a compact clock display.
- **Volume and brightness** — quick access to system adjustments.
- **Battery indicator** — check battery status.
- **App launcher** — open applications and websites.
- **File shelf** — keep files nearby by dropping them onto the interface.

### Settings

Configure the available features and interaction options from the settings window. Some features require macOS permissions.

## Build from source

### Requirements

- macOS 14 Sonoma or later.
- Xcode or Apple's Command Line Tools.

### Build the app

```bash
git clone https://github.com/maTTvey-web/GlassNotch.git
cd GlassNotch/GlassNotch
bash build.sh
open build/GlassNotch.app
```

### Create a DMG

Run this on a Mac:

```bash
bash make-dmg.sh
```

The script builds the app and creates `GlassNotch.dmg` in the repository's root directory.

## Permissions

GlassNotch may request access to:

- **Automation** to communicate with Spotify and Apple Music.
- **Calendar** to display events.
- **Browser media information** for supported browser playback controls.

Grant only the permissions needed for the features you use.

## Notes

- Browser playback information depends on browser support and the website's media session.
- Some features may need additional macOS permissions.
- The app is built for macOS and is not intended for Windows or Linux.

## License

GlassNotch is available under the [MIT License](GlassNotch/LICENSE).

## Links

- [GitHub repository](https://github.com/maTTvey-web/GlassNotch)
- [Releases](https://github.com/maTTvey-web/GlassNotch/releases)
- [Issues and bug reports](https://github.com/maTTvey-web/GlassNotch/issues)

---

<p align="center">
  Made by <a href="https://github.com/maTTvey-web">MaTTvey-web</a>
</p>
