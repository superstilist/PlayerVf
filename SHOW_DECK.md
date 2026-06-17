# PlayerVf — Show Deck

> **One beautiful player. Every device. Your library, your rules.**

---

## 1. The Hook

You love your music. You hate switching between five different apps to play it.

PlayerVf is a **single, cross-platform music & video player** built in Flutter that runs on Android, iOS, Windows, macOS, Linux, and the Web — with a design that feels premium on every screen size.

**Tagline:** *PlayerVf powered by Wrench — your media, unified.*

---

## 2. The Problem

- Streaming apps lock your library behind subscriptions.
- Desktop music players look like they were designed in 2005.
- Most players pick a lane: *local OR streaming*, *audio OR video*, *mobile OR desktop*.
- Customization is either nonexistent or buried in config files.

Music lovers who own their files deserve a player as good as the ones shipping inside streaming services.

---

## 3. The Solution

PlayerVf is a **unified playback shell** that combines:

| Capability | What it means |
|---|---|
| Local library | Auto-scan, smart playlists, custom playlists |
| Streaming | Built-in YouTube Music search, stream, and download |
| Audio + Video | One engine, both media types, with subtitles |
| Sharing | LAN library sync + Android Wi-Fi Direct |
| Deep theming | 9 presets, custom accents, particle FX, glass UI |

---

## 4. Product Tour

### 🎵 Library
- Auto-scans configured music folders (or imports a web folder).
- Reads ID3, MP4, FLAC, APE metadata; extracts cover art and sidecar assets.
- Remembers favorites, play counts, last-played, and your listening history across restarts.
- System smart playlists: **Favorites, Recent, Most Listened, Daily Mix, Early Listened**.

### ▶️ Playback
- Play / pause / next / previous / seek / volume / mute / shuffle / repeat (all / one).
- Configurable gap between songs, **gapless** transitions, resume-after-restart.
- Full **audio engine** via `media_kit` (libavfilter / MPV) with:
  - 10-band equalizer with presets
  - Pitch, speed, and reverb
  - Per-song or global effect profiles
  - Native Windows audio filters with software fallback

### 🎬 Video
- Local + YouTube video playback.
- Subtitle support: file, URL, or auto sidecar detection.
- Quality switching (local + stream), fullscreen, double-tap to fullscreen, live cover-art background.

### 📝 Lyrics
- Sidecar `.lrc` and plain-text lyrics.
- **Online lyrics search** with one-tap save.
- Editable, fullscreen, auto-scrolling, time-synced.

### 📥 YouTube Music
- Search YouTube Music by query, filter by result type.
- **Stream without downloading** OR download audio / video / subtitles.
- Choose quality and subtitle language (auto or manual).
- Stream URL caching and warm-cache for upcoming results.

### 🔁 Sharing
- Spin up a local HTTP share server for your current song or entire library.
- **Discover** other PlayerVf instances on the LAN and pull their tracks.
- **Wi-Fi Direct** discovery / connect / transfer on Android.
- Progress, speed, pause / resume / cancel, dedup, optional backup-before-import.

### 🏷️ Metadata & Covers
- Edit title / artist / album / genre.
- Pick custom cover art or auto-lookup via **MusicBrainz** (auto + manual search with scored matches).
- Use cover palette colors as live player backgrounds.

### 🎨 Appearance
- **9 theme presets**: Material, Graphite, Classic, Fox, Anime, Azure, Cosmic, Sunset, Midnight.
- **Dark / Light / System** mode.
- Accent color picker + RGB sliders.
- Glass effect intensity, border radius, font size.
- **Particle backgrounds**: Sakura, Snow, Stars, Bubbles, Rain, None.
- 4 nav positions (top, bottom, left, right) — first-class desktop UX.
- Card / list view, adjustable card size, margins, and grid count.

### ⌨️ Desktop & Keyboard
- Global shortcuts: play/pause, next, prev/restart, seek, volume, mute, search, fullscreen.
- **Windows SMTC** integration (media keys, lockscreen controls).
- Window-manager fullscreen toggle, smooth scroll, typing-guard for shortcuts.

---

## 5. Technical Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Flutter UI (Material 3)                    │
│  Pages: Home • Favorites • Playlists • Player • Video       │
│         YouTube Music • Share • Settings • Appearance      │
├─────────────────────────────────────────────────────────────┤
│                   State (provider)                          │
│   SettingsModel • MusicService • PlayerAudioHandler         │
├─────────────────────────────────────────────────────────────┤
│         Playback     │   Discovery   │   Discovery          │
│   media_kit + video  │  local HTTP   │  Wi-Fi Direct        │
│   just_audio + SMTC  │   share       │   (Android)          │
│   audio_session      │  service      │                      │
├─────────────────────────────────────────────────────────────┤
│   Library    │  Metadata  │  Covers   │  YouTube Music       │
│  scanner +   │  id3 +     │  extractor│  Python helper       │
│  on_audio_   │  flutter_  │  + palette│  (desktop + Android) │
│  query       │  media_    │  generator│                      │
│              │  metadata  │           │                      │
├─────────────────────────────────────────────────────────────┤
│   Storage: sqflite (cache)  •  shared_preferences (state)  │
│   Files:   music paths  +  YouTube DL path  +  sync dir     │
└─────────────────────────────────────────────────────────────┘
```

### Stack
- **Flutter 3.4+** / Dart 3
- **media_kit** + **media_kit_video** for unified audio/video playback
- **just_audio** + **audio_service** + **smtc_windows** for system media session
- **provider** for reactive state
- **sqflite** + **shared_preferences** for persistence
- **id3** + **flutter_media_metadata** for tag parsing
- **on_audio_query** + **permission_handler** for mobile media access
- **palette_generator** + **image** for cover-derived theming
- **Python** (`yt-dlp`, `ffmpeg`) bridge for YouTube Music on desktop and Android

---

## 6. Platform Matrix

| Platform | Min Version | Status |
|---|---|---|
| Android | API 21+ | ✅ |
| iOS | 13.0+ | ✅ |
| Windows | 10+ | ✅ |
| macOS | 10.15+ | ✅ |
| Linux | Ubuntu 18.04+ | ✅ |
| Web | Modern browsers | ✅ (web folder import) |

---

## 7. Why PlayerVf Wins

1. **One app, every device** — phone, tablet, laptop, desktop, browser. Same library, same look.
2. **Local-first, streaming-augmented** — your files come first; YouTube Music is an add-on, not a cage.
3. **Truly customizable** — themes, accents, glass, particles, layouts. Pixel-pushers welcome.
4. **First-class desktop** — keyboard shortcuts, SMTC, window manager, hardware decoder toggles, battery-saver mode.
5. **Real sharing** — not "share to social"; share your actual library over Wi-Fi.
6. **Modern media engine** — equalizer, pitch, speed, reverb, gapless, subtitles, quality switching.

---

## 8. Live Demo Path

1. Launch app → auto-scans configured music folder.
2. Show **Home** smart playlists (Favorites, Recent, Most Listened).
3. Play a track → open full player → switch **theme preset** live (Midnight → Sunset).
4. Switch to **YouTube Music** tab → search → stream without download.
5. Open **Share** → start server → show another instance discovering it.
6. Drop into **Appearance** → toggle Sakura particles + glass intensity.
7. Switch to **grid view** in Settings → change nav position to **left rail** (desktop feel).

---

## 9. Roadmap (Next)

- Cloud sync of library + settings
- Collaborative listening rooms (extends the LAN share model)
- Plugin SDK for third-party sources (Spotify, SoundCloud)
- Lyrics translation overlay
- Mobile widgets (home-screen mini player)

---

## 10. Try It

- **Web demo:** https://superstilist.github.io/playervf-web/
- **Source:** `github.com/superstilist/PlayerVf`
- **License:** MIT
