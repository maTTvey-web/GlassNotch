<div align="center">

# GlassNotch

### A smarter, more personal notch for macOS.

A lightweight macOS notch companion for music, browser playback, calendar events, files, and everyday productivity — wrapped in a clean, animated interface.

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-111111?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://www.swift.org/)
[![License](https://img.shields.io/badge/License-MIT-8A8A8A?style=for-the-badge)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS-black?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/mac/)

[Features](#-features) · [Widgets](#-built-in-widgets) · [Screenshots](#-screenshots) · [Installation](#-installation) · [Build from Source](#-build-from-source) · [Permissions](#-permissions)

</div>

---

## Overview

**GlassNotch** turns the space around your Mac's notch into a useful, interactive workspace. It keeps important information close at hand without requiring you to switch between apps.

Check what's playing, control supported music sources, glance at your calendar, keep files nearby, or start a focus session — all from one compact interface designed to feel at home on macOS.

- **Native macOS app** built with Swift and SwiftUI.
- **Interactive notch interface** that expands to reveal more information and controls.
- **Customizable appearance** with adjustable sizing, corner roundness, animation speed, and accent colors.
- **Multiple productivity features** available from one place.
- **Multilingual interface** with system-language detection and manual language selection.

> GlassNotch is an independent project and is not affiliated with or endorsed by Apple.

## ✨ Features

<table>
  <tr>
    <td width="50%">
      <h3>🎵 Music controls</h3>
      View track information and artwork, check playback progress, and control supported music players.
    </td>
    <td width="50%">
      <h3>🌐 Browser playback</h3>
      Detect supported media sessions in compatible browsers and control playback without switching windows.
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>📅 Calendar</h3>
      See today's events and upcoming meeting information directly from the notch.
    </td>
    <td width="50%">
      <h3>📂 File shelf</h3>
      Keep files close at hand with a shelf that can appear around the notch.
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>🔋 Battery and clock</h3>
      Show battery status, a low-battery indicator, and an optional clock display.
    </td>
    <td width="50%">
      <h3>⏱ Focus timer</h3>
      Start focus and break sessions with configurable durations and an optional timer sound.
    </td>
  </tr>
  <tr>
    <td width="50%">
      <h3>🚀 Quick open</h3>
      Add apps and websites for quick access from the expanded interface.
    </td>
    <td width="50%">
      <h3>🎨 Personalization</h3>
      Adjust the notch appearance, accent color, panel dimensions, animation speed, and behavior.
    </td>
  </tr>
</table>

## 🧩 Built-in widgets

GlassNotch brings several small tools together in a single interface. Features can be enabled or disabled in Settings where supported.

### Music

- Track title, artist, artwork, and playback progress.
- Playback controls for supported native music apps.
- Optional artwork and equalizer elements beside the collapsed notch.
- Browser media support for compatible sites, including YouTube, SoundCloud, Spotify Web, Apple Music on the web, Deezer, Tidal, and Bandcamp.
- Browser selection controls for supported browsers.

**Native players:** Spotify and Apple Music.  
**Supported browsers:** Safari, Google Chrome, Brave, Microsoft Edge, and Arc. Browser controls depend on the browser's automation settings and the website's media-session support.

### Calendar and meetings

- Today's calendar events.
- Meeting information in the notch.
- Optional reminders before meetings.
- Calendar access can be managed through macOS privacy settings.

### File shelf

- Keep selected or dropped files available from the notch.
- Show or hide the floating shelf indicator.
- Clear the shelf when you no longer need its contents.

### Battery and clock

- Battery percentage and low-battery indicator.
- Configurable low-battery threshold.
- Optional clock island and seconds display.

### Focus timer

- Configurable focus and break durations.
- Start a focus or break session from the expanded panel.
- Optional timer sound.

### Quick open and notes

- Add apps for quick launching.
- Save websites for quick access.
- Website icons and names can be filled from a pasted link where available.
- Create and manage short notes.

## 🖼️ Screenshots

Screenshots make it easier to understand the interface at a glance. Add the actual project screenshots to `assets/screenshots/` using the filenames below; these image slots are intentionally not represented as real screenshots until those files are added.

<div align="center">

| Main interface | Expanded panel |
|:--:|:--:|
| `assets/screenshots/overview.png` | `assets/screenshots/expanded-panel.png` |
| *Collapsed notch and surrounding elements* | *Expanded interface and available widgets* |

| Music controls | Settings |
|:--:|:--:|
| `assets/screenshots/music-controls.png` | `assets/screenshots/settings.png` |
| *Track details and playback controls* | *Appearance and feature customization* |

| File shelf | Calendar and focus |
|:--:|:--:|
| `assets/screenshots/file-shelf.png` | `assets/screenshots/calendar-focus.png` |
| *Files kept close at hand* | *Events, meetings, and focus timer* |

</div>

Once the images are committed, replace this table with embedded images, for example:

```md
<div align="center">
  <img src="assets/screenshots/overview.png" width="48%" alt="GlassNotch main interface">
  <img src="assets/screenshots/expanded-panel.png" width="48%" alt="GlassNotch expanded panel">
</div>
```

Recommended screenshots: use a clean macOS desktop, capture the notch in both collapsed and expanded states, and include separate images for music, settings, and the file shelf. Avoid including personal notifications, private calendar details, or other sensitive information.

## ⚙️ Installation

### Option 1 — Download a release

1. Open the [GlassNotch Releases](https://github.com/maTTvey-web/GlassNotch/releases) page.
2. Download the `.dmg` file if a release is available.
3. Open the disk image.
4. Drag `GlassNotch.app` into **Applications**.
5. Launch GlassNotch and grant the requested macOS permissions for the features you want to use.

If no release is published yet, use the build-from-source instructions below.

### Option 2 — Build the DMG locally

**Requirements**
- A Mac running macOS 14 or later.
- Xcode or the Xcode Command Line Tools.
- Swift compiler and standard macOS build utilities.

1. Clone the repository:

   ```bash
   git clone https://github.com/maTTvey-web/GlassNotch.git
   cd GlassNotch
   ```

2. Build the app and create the disk image:

   ```bash
   cd GlassNotch
   bash make-dmg.sh
   ```

3. The generated `GlassNotch.dmg` is placed in the repository's root directory.

4. Open the DMG and drag the app into Applications.

## 🛠️ Build from Source

To build the `.app` bundle without creating a DMG:

```bash
git clone https://github.com/maTTvey-web/GlassNotch.git
cd GlassNotch/GlassNotch
bash build.sh
```

The application bundle will be created at:

```text
GlassNotch/build/GlassNotch.app
```

You can launch it from Terminal with:

```bash
open build/GlassNotch.app
```

The build script uses the Swift compiler and signs the local application bundle with an ad-hoc signature. This is a local development build, not an Apple Developer ID-signed distribution.

## 🔐 Permissions

GlassNotch uses macOS permissions to provide specific integrations. Grant only the permissions required for the features you use.

| Permission | Why it may be needed |
|---|---|
| **Accessibility** | Browser automation and supported playback controls. |
| **Automation / Apple Events** | Reading or controlling supported music apps and browser tabs. |
| **Calendar access** | Displaying today's events and meeting information. |
| **Browser JavaScript access** | Reading media-session details and controlling playback in supported browser tabs. |

For Safari, you may need to enable **Develop → Allow JavaScript from Apple Events**. Without it, browser media information or controls may be limited.

If a feature does not work, check **System Settings → Privacy & Security** and the relevant browser settings, then restart the feature.

## 🎨 Customization

Open **Settings** from GlassNotch to configure available options, including:

- **Language:** follow the system language or select a supported language manually.
- **Launch at login:** choose whether GlassNotch opens when you sign in.
- **Interaction:** open the panel on hover or switch to click-based interaction.
- **Appearance:** change the notch color and accent color, including artwork-based accent behavior.
- **Dimensions:** adjust the expanded panel width, height, and corner roundness.
- **Animation:** tune the animation speed.
- **Widgets:** configure music, browser scanning, calendar, battery, clock, and file shelf options.
- **Work tools:** configure meeting reminders, focus duration, break duration, and timer sound.

Available options may vary with the app version and macOS permissions.

## 🌍 Languages

GlassNotch includes these language options:

- English
- Español
- Français
- 日本語
- Русский
- System language

When **System** is selected, GlassNotch uses the macOS language when it is supported and falls back to English otherwise.

## 🧱 Tech Stack

- **Swift** — application logic.
- **SwiftUI** — interface and animations.
- **AppKit** — macOS application and window integration.
- **EventKit** — calendar events.
- **IOKit Power Sources** — battery information.
- **AppleScript / JavaScript for Automation** — supported media and browser integrations.
- **GitHub Actions** — automated DMG build workflow.

## 📁 Project Structure

```text
GlassNotch/
├── .github/
│   └── workflows/
│       └── build.yml
├── GlassNotch/
│   ├── Sources/
│   │   └── GlassNotchApp.swift
│   ├── Info.plist
│   ├── build.sh
│   ├── make-dmg.sh
│   └── LICENSE
├── .gitignore
└── README.md
```

The build workflow can create a DMG artifact manually or when a version tag matching `v*` is pushed.

## 🗺️ Roadmap

Ideas for future development:

- [ ] Add and maintain a dedicated gallery of real screenshots.
- [ ] Continue refining animations and interaction details.
- [ ] Improve setup guidance for browser permissions and integrations.
- [ ] Expand documentation as features evolve.

## 🤝 Contributing

Suggestions, bug reports, and improvements are welcome.

1. Check the existing [issues](https://github.com/maTTvey-web/GlassNotch/issues) before opening a new one.
2. Describe the problem or suggestion clearly.
3. Include macOS version, GlassNotch version, and steps to reproduce issues where relevant.
4. Avoid sharing private calendar information, personal files, or other sensitive data in bug reports.

## 📄 License

GlassNotch is distributed under the [MIT License](LICENSE).

## 👤 Author

**MaTTvey-web**

- GitHub: [@maTTvey-web](https://github.com/maTTvey-web)
- Project: [GlassNotch](https://github.com/maTTvey-web/GlassNotch)

---

<div align="center">

**GlassNotch** — useful details, right where you need them.

If you like the project, consider giving the repository a ⭐.

</div>
