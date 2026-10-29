<div align="center">

# GlassNotch

**A Dynamic Island-style notch for macOS.**

Music, files, meetings and handy controls — right from the top of your screen.

[Download](https://github.com/maTTvey-web/GlassNotch/releases/latest) · [Features](#features) · [Install](#installation)

![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

</div>

---

## Preview

A quick look at how GlassNotch can sit around the MacBook notch. These are **concept previews**, not screenshots captured from the running app.

<p align="center">
  <img src="assets/screenshots/music-island.svg" alt="GlassNotch music island preview" width="49%" />
  <img src="assets/screenshots/file-shelf.svg" alt="GlassNotch file shelf preview" width="49%" />
</p>

## Features

- **Music controls** — control Spotify and Apple Music, with track progress and artwork where available.
- **Browser audio** — show media from supported tabs in Chrome, Brave, Edge, Arc and Safari, including sites such as YouTube and SoundCloud.
- **File shelf** — drop files onto the notch, open them from there, or drag them back out.
- **Calendar** — see upcoming events and meeting links, with a Join button when a supported link is available.
- **Focus timer and notes** — keep a Pomodoro timer or quick note close by.
- **Quick open** — launch an app or open a website from the notch.
- **Useful controls** — clock with seconds, volume and brightness sliders, plus a low-battery reminder.
- **Personal settings** — change the accent/notch colours, choose hover or click behaviour, and turn individual features on or off.

## Installation

### Option 1 — Download a release

1. Open **[GlassNotch Releases](https://github.com/maTTvey-web/GlassNotch/releases/latest)**.
2. Download `GlassNotch.dmg` if it is attached to the latest release.
3. Open the DMG and move `GlassNotch.app` to **Applications**.
4. Launch GlassNotch. Its icon will appear in the menu bar.
5. Open **System Settings → Privacy & Security** and allow the permissions macOS requests for the features you want to use.

> If the Releases page has no downloadable DMG yet, use Option 2 below.

### Option 2 — Build it from the source

**Requirements:** macOS 14 or later, plus Xcode or Apple's Command Line Tools.

1. Download the repository using **Code → Download ZIP**, then unzip it.
2. Open Terminal and move into the project folder:

   ```bash
   cd GlassNotch/GlassNotch
   ```

   The exact folder path can differ depending on where you unzipped the archive.

3. Build the app:

   ```bash
   bash build.sh
   ```

4. Launch it:

   ```bash
   open build/GlassNotch.app
   ```

The app bundle will be created in `GlassNotch/build/GlassNotch.app`.

### First launch and permissions

- **Music:** open Spotify or Music first, then allow GlassNotch to control it when macOS asks.
- **Browser music:** enable browser access in GlassNotch settings. macOS may ask for Accessibility and Automation access; allow them if you want this feature.
- **Calendar:** allow calendar access to show upcoming events.

You can change these options later from the GlassNotch menu bar icon → **Settings…**.

## Notes

- GlassNotch is designed for macOS 14 and newer.
- Browser media support depends on the browser and whether the page exposes media-session controls.
- Apple Music artwork may use a placeholder. Spotify artwork is supported.
- On macOS 15.4 and newer, Apple's private MediaRemote API is no longer available to third-party apps, which limits support for some native players.

## Build a DMG

From the project folder, run:

```bash
bash make-dmg.sh
```

The script creates `GlassNotch.dmg` if the required Apple build tools are installed.

## Tech

- Swift
- SwiftUI
- AppleScript for supported media controls
- EventKit for calendar events

## License

GlassNotch is released under the [MIT License](GlassNotch/LICENSE).

---

<div align="center">

Made by [MaTTvey-web](https://github.com/maTTvey-web)

</div>
