# GlassNotch

A Dynamic Island-style notch for MacBooks, written in SwiftUI.

- GlassNotch that melts into the screen edge and morphs with spring animations
- Separate floating "islands" that fly out of the notch (music, file shelf) and merge back when it opens
- Music controls, progress and artwork for Spotify, Apple Music and browser tabs (YouTube, SoundCloud, Spotify Web)
- Next meeting island with a Join button (Zoom / Meet / Teams links from your calendar)
- Focus timer (Pomodoro) and quick notes
- Clock with seconds, volume and brightness sliders
- Low-battery island (hover it for a reminder to plug in)
- Quick open: pick an app or paste a site, icon is read automatically
- File shelf: drop files on the notch, click to open, drag them back out
- Settings window (menu bar icon → Settings…): launch at login, hover/click, toggles per feature

## Build
Requires macOS 14+ and Xcode or Command Line Tools.

```bash
bash build.sh
open build/GlassNotch.app
```
On first launch macOS asks for permission to control Spotify / Music.

## Browser music
Works through AppleScript + `navigator.mediaSession` in Chrome, Brave, Edge, Arc and Safari (YouTube, SoundCloud, Spotify Web, ...).
Settings -> Music -> "Allow browser access" turns on "Allow JavaScript from Apple Events" in the browser for you.
Safari is switched on by the same button (it opens Settings > Advanced for you); if that fails: Develop > Allow JavaScript from Apple Events. Each browser can be switched on/off in Settings.

## Limitations
- Apple closed the private MediaRemote API in macOS 15.4, so other native players are not supported. Add AppleScript-capable players to the `Player` enum.
- Apple Music artwork is a placeholder; Spotify artwork works.

## License
MIT
