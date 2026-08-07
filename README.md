# PlayerVF powered by Wrench

![PlayerVF Logo](https://github.com/superstilist/PlayerVf/blob/master/assets/logo.png)

[Web App](https://superstilist.github.io/playervf-web) | [Site](https://superstilist.github.io/PlayerVf/)

A cross-platform music and video player built with Flutter. Local library scanning, YouTube Music streaming/download, lyrics, audio effects, video playback, playlists, nearby sharing, and deep visual customization.

---

## Features at a Glance

| Category | Highlights |
|----------|-----------|
| Playback | Play/pause, seek, queue, shuffle, repeat, gap control, resume on launch |
| Library | Auto-scan, metadata extraction, cover art, smart playlists, search |
| Audio Effects | Equalizer, pitch, speed, reverb, tone controls, safe ears mode |
| Video | Local playback, YouTube streaming, fullscreen, subtitles, quality switching |
| Lyrics | Timed LRC, plain text, online search, fullscreen karaoke, romaji |
| YouTube Music | Search, stream, download audio/video/subtitles, quality selection |
| Playlists | Create, rename, delete, add/remove tracks, cover collages |
| Favorites | Toggle favorite, dedicated page, multi-select |
| Sharing | Local network server, device discovery, track transfer, Wi-Fi Direct |
| Artist Info | MusicBrainz lookup, biography, related artists, YouTube Music results |
| Metadata | Edit tags, auto-tag with MusicBrainz, custom cover art |
| Appearance | 9 theme presets, accent color picker, particles, orbs, glass effects |
| Desktop | Fullscreen, keyboard shortcuts, window manager, SMTC |

---

## Playback

- **Transport Controls** -- play, pause, next, previous, restart, seek forward/backward.
- **Volume** -- slider and keyboard shortcuts (ArrowUp/Down, M for mute).
- **Shuffle** -- separate shuffled queue alongside normal queue.
- **Repeat** -- repeat all, repeat one, repeat off.
- **Queue** -- start from any track list, drag-and-drop reorder, add/remove items.
- **Resume** -- saves track and position; restores on next launch.
- **Song Gap** -- configurable silence between tracks (0-5000ms).
- **Smooth Transitions** -- fade-in/fade-out on play/pause, smooth volume ramping.
- **Streaming** -- play YouTube Music results directly without downloading.
- **Keyboard Shortcuts** -- Space (play/pause), N (next), B (previous), R (restart), Arrow keys (seek/volume), Enter (open player), Escape (close player), F11 (fullscreen).
- **Media Session** -- OS-level media controls (taskbar, lock screen, notification shade).
- **Windows SMTC** -- System Media Transport Controls with metadata and timeline.

## Audio Effects

- **Equalizer** -- enable/disable, adjustable bands, preset selection, reset to flat.
- **Pitch** -- adjustable playback pitch.
- **Speed** -- adjustable playback speed.
- **Reverb** -- adjustable reverb level.
- **Tone Controls** -- bass, mid, treble (-6dB to +6dB each).
- **Safe Ears** -- caps max volume (35%-100%) with presets at 60/70/80/90%.
- **Per-Song Effects** -- toggle between global and per-track effect settings.
- **Real-Time DSP** -- loudness normalization, peak limiter, smooth compressor.
- **Engine** -- native Windows audio filter when available, MPV/libavfilter fallback.

## Library

- **Auto-Scan** -- scans configured folders and device media store.
- **Supported Formats** -- MP3, M4A, WAV, FLAC, AAC, OGG, Opus, WMA, MP4, MKV, WebM, AVI, MOV.
- **Metadata Extraction** -- ID3v2, ID3v1, APE, MP4 atoms, FLAC Vorbis, Android MediaStore, filename fallback.
- **Cover Art** -- embedded art extraction from MP3/MP4/FLAC, sidecar image detection.
- **Persistence** -- library, favorites, play counts, and metadata survive app restarts.
- **Web Import** -- import from browser-selected folder on web platform.
- **Custom Source Folders** -- add/remove/clear multiple music directories.
- **Delete Tracks** -- remove individual songs from the library and filesystem.
- **Clear Cache** -- wipe cached data and rescan.

### Smart Playlists
- Recommended to Listen
- Early Listened (older history)
- Recently Added
- Favorites
- Most Listened
- Daily Mix

## Video

- **Local Video** -- plays MP4, MKV, WebM, AVI, MOV, M4V.
- **YouTube Streaming** -- stream YouTube videos with quality selection.
- **Fullscreen** -- dedicated fullscreen player with auto-hiding controls.
- **Double-Tap Fullscreen** -- configurable gesture to enter fullscreen.
- **Quality Switching** -- switch between available qualities mid-playback.
- **Subtitles** -- load from file or URL (SRT, VTT, ASS, SSA).
- **Auto Sidecar** -- auto-detect subtitle files next to the video.
- **Live Background** -- optionally play video behind the player UI.
- **Decoder Modes** -- auto/software/hardware for both audio and video.

## Lyrics

- **Sidecar Loading** -- loads .lrc, .txt, or .lyrics files next to the track.
- **Timed Lyrics** -- parses `[mm:ss.xx]` timestamps for line-by-line highlighting.
- **Plain Lyrics** -- supports lyrics without timestamps.
- **Online Search** -- searches LRCLIB for lyrics using track metadata.
- **Custom Search** -- search with user-provided title/artist/album/duration.
- **Save Locally** -- saves fetched lyrics as sidecar files.
- **Edit Lyrics** -- edit current lyrics in-place.
- **Romaji** -- optional Japanese-to-Latin transliteration.
- **Spicy Lyrics Engine v2** -- word-by-word highlight, karaoke transitions, GIF backgrounds, custom colors.

### Fullscreen Lyrics Customization
- Position (top/center/bottom), alignment (left/center/right)
- Cover art, track name, controls, progress -- each togglable
- Font scale (0.5x-3.0x), dim background (25%-85%)
- Header/cover styles (compact, big cover, glow, shadow, circle)
- Controls styles (classic, pill, minimal, glow, 4:3 panel)
- Special effects (soft glow, pulse, float, particles)
- Particle packs (sparkles, stars, snow, bubbles, hearts, sakura, fireflies, confetti, custom)
- Custom layout mode with free positioning of all elements
- Per-element offset, scale, rotation, layer, opacity
- Up to 12 custom visual overlay items

## YouTube Music

- **Search** -- search by query with filter options (songs, videos).
- **Stream** -- play results directly via resolved stream URL.
- **Download Audio** -- download audio-only (MP3/M4A).
- **Download Video** -- download at selectable quality.
- **Download Subtitles** -- SRT, VTT, ASS, SSA files.
- **Quality Selection** -- choose from available resolutions.
- **Downloaded Tracking** -- marks already-downloaded items.
- **Stream Cache** -- caches stream URLs for faster re-playback.
- **Python Backend** -- uses yt-dlp via Python on desktop and Android.

## Playlists

- **Create / Rename / Delete** -- full playlist management.
- **Add / Remove Tracks** -- add individual or multi-selected songs.
- **Play Playlist** -- start playback of all tracks.
- **Cover Collage** -- 2x2 collage from first 4 songs in the playlist.
- **Responsive Grid** -- adaptive 2-5 columns based on screen width.

## Favorites

- **Toggle** -- heart icon on any track.
- **Dedicated Page** -- all favorited tracks in grid or list.
- **Multi-Select** -- bulk operations on selected favorites.
- **Search** -- real-time filtering within favorites.

## Sharing / Nearby

- **Local Server** -- HTTP server on local network.
- **Share Current or Full Library** -- choose what to share.
- **Device Discovery** -- scan for other PlayerVF devices.
- **Wi-Fi Direct** -- Android peer-to-peer connection support.
- **Track Transfer** -- download tracks with progress, speed, pause/resume/cancel.
- **Duplicate Detection** -- avoids re-downloading existing files.
- **Sync Directory** -- synced files auto-added to library.
- **Listen Together** -- initiate a shared listening session.
- **Backup Before Import** -- optional library backup before importing shared tracks.

## Artist Info

- **MusicBrainz Lookup** -- automatic artist info from MusicBrainz API.
- **Cover Art** -- MusicBrainz cover art archive, Wikidata P18 image fallback.
- **Biography** -- expandable bio section.
- **Metadata Chips** -- country, active years, album count.
- **Related Artists** -- horizontal scrollable list.
- **External Links** -- MusicBrainz, Last.fm, Wikidata, and more.
- **Local Songs** -- tracks in your library matching the artist.
- **YouTube Music** -- auto-searches YouTube Music for the artist.

## Metadata

- **View Details** -- title, artist, album, genre, year, duration, file path, play count, last played, date added.
- **Edit Metadata** -- edit title, artist, album, genre, year.
- **Custom Cover Art** -- pick any image as cover art.
- **MusicBrainz Auto-Tag** -- one-tap auto-tag from MusicBrainz.
- **MusicBrainz Manual Search** -- search by title/artist/album.
- **Scored Results** -- ranked matches for user selection.

## Appearance / Theme

### Theme Presets (9)
- Material -- clean Material Design
- Graphite -- dark, subdued tones
- Classic -- fully customizable
- Fox -- warm orange accent + snow particles
- Anime -- pink accent + sakura particles
- Azure -- blue accent + bubble particles
- Cosmic -- purple accent + star particles
- Sunset -- red/coral accent
- Midnight -- indigo accent + rain particles

### Customization
- **Theme Mode** -- light, dark, or system.
- **Accent Color** -- full HSV picker with RGB fields, HEX input, 12 presets.
- **Background Style** -- blurred cover art, custom image, or solid color with orb effect.
- **Particles** -- 11 options (none, sakura, snow, stars, bubbles, rain, hearts, fireflies, confetti, orbs, custom symbols).
- **Orb Effect** -- size, speed, palette colors derived from cover art.
- **Navigation Position** -- top, bottom, left, right.
- **Library Layout** -- card (grid) or list view.
- **Grid Card Size** -- 80-300px adjustable.
- **Spacing** -- 0-32px between cards.
- **Font Size** -- 10-20pt.
- **Border Radius** -- 0-40px.
- **Glass Effect** -- 0%-100% transparency/frosted-glass intensity.
- **Cover Art Display** -- fit, crop, square, or custom.

## Performance

- **5 Modes** -- Auto, Quality, Balanced, Battery Saver, Max Performance.
- **Performance Policy** -- controls decorative animations, particles, blur, cache sizes.
- **Image Cache** -- platform-adaptive (Android: 240/96MB, Desktop: 420/192MB, Web: 160/72MB).

## Desktop

- **Fullscreen** -- F11 toggle via window_manager.
- **Keyboard Guard** -- catches duplicate key-down assertions on Windows.
- **Smooth Scroll** -- mouse, trackpad, stylus, and touch dragging.
- **Platform Transitions** -- FadeUpwards (Windows/Linux), Cupertino (macOS/iOS), Zoom (Android).

## Responsive Design

- Adaptive grid: 2 columns (<330px) to 6 columns (1200px+).
- Tablet/phone/desktop detection.
- Proportional sizing helpers (`.w`, `.h`, `.sp`, `.s`).
- Mini player position adapts to navigation layout.

---

## Platform Support

| Platform | Min Version | Status |
|----------|-------------|--------|
| Android | API 21+ | Full support |
| Windows | 10+ | Full support |
| macOS | 10.15+ | Full support |
| Linux | Ubuntu 18.04+ | Full support |
| Web | Modern browsers | Partial (streaming, web import) |
| iOS | 13+ | Intended |

---

## Installation

### Prerequisites
- Flutter 3.4.0+ installed
- Python 3.8+ (for YouTube Music features on desktop)
- yt-dlp (installed automatically via requirements.txt)

### Setup

```bash
git clone https://github.com/superstilist/PlayerVf.git
cd PlayerVf
flutter pub get
```

### Run

```bash
# Android
flutter run

# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Linux
flutter run -d linux

# Web
flutter run -d chrome
```

### Build

```bash
# Android APK
flutter build apk --release

# Windows EXE
flutter build windows --release

# macOS App
flutter build macos --release

# Linux AppImage
flutter build linux --release

# Web
flutter build web --release
```

---

## Project Structure

```
lib/
  main.dart                        App entry, providers, theming, navigation
  models/
    music_model.dart               Music data model
    playlist_model.dart            Playlist model
    settings_model.dart            Settings enums and persistence
    lyrics_model.dart              Lyrics parsing and data
    cover_model.dart               Cover art model
    artist_info.dart               Artist info from MusicBrainz
    page_state.dart                Navigation state
  pages/
    home_screen.dart               Library home with smart playlists
    player_page.dart               Full audio player
    video_page.dart                Video player with fullscreen
    favorite_page.dart             Favorites list
    playlist_page.dart             Playlist overview
    playlist_detail_page.dart      Playlist tracks
    artist_page.dart               Artist info page
    settings_screen.dart           Settings page
    settings_page.dart             Settings page (alternate)
    playback_settings_screen.dart  Playback settings
    appearance_screen.dart         Appearance customization
    lyrics_sheets.dart             Lyrics bottom sheet
    fullscreen_lyrics_page.dart    Fullscreen lyrics
    youtube_music_page.dart        YouTube Music search/stream/download
    share_page.dart                Local sharing UI
    unified_search_page.dart       Global search
    records_page.dart              Library view
    library_stats_screen.dart      Library analytics
    web_settings_screen.dart       Web/YouTube settings
  services/
    music_service.dart             Central player/library/state service
    music_scanner_service.dart     File scanning and metadata
    musicbrainz_service.dart       MusicBrainz API integration
    artist_image_service.dart      Wikidata artist images
    musicbrainz_tag_service.dart   MusicBrainz tag lookup/scoring
    cover_color_service.dart       Cover art color palette extraction
    cover_extractor.dart           Cover art extraction from files
    youtube_music_service.dart     YouTube Music Python bridge
    player_audio_handler.dart      OS media controls integration
    local_share_service.dart       Local network sharing
    wifi_direct_service.dart       Android Wi-Fi Direct
    id3_parser.dart                Metadata tag parsing
    audio_analyzer.dart            Audio analysis
    performance_policy.dart        Performance mode control
    responsive.dart                Responsive sizing helpers
    orb_controller.dart            Orb animation controller
    debug_service.dart             Debug utilities
    safe_file_picker.dart          Safe file picking
  widgets/
    music_card.dart                Song card/list item with actions
    playlist_card.dart             Playlist card
    cover_art_texture.dart         Cover art renderer
    glass_container.dart           Frosted glass container
    particle_system.dart           Animated background particles
    orb_system.dart                Orb animation system
    audio_effects_menu.dart        Audio effects bottom sheet
    playback_progress_control.dart Progress bar/scrubber
    stable_video_surface.dart      Video surface wrapper
    blurred_cover_background.dart  Blurred cover background
    lanczos_cover_art.dart         High-quality cover scaling
    lyrics_view.dart               Lyrics display widget
    fade_in_up_animation.dart      Entrance animation
    settings_drawer.dart           Settings drawer
  python/
    api.py                         Desktop Python backend
    requirements.txt               Python dependencies
assets/
  logo.png                         App logo
  fonts/                           NotoSans, NotoSansJP, NotoSansSC
```

---

## Key Dependencies

| Library | Purpose |
|---------|---------|
| media_kit / media_kit_video | Audio/video playback engine |
| audio_service / just_audio | Background audio and media session |
| smtc_windows | Windows System Media Transport Controls |
| provider | State management |
| shared_preferences | Persistent settings |
| sqflite / sqflite_common_ffi | SQLite database for library cache |
| palette_generator / image | Cover art color extraction |
| on_audio_query | Android MediaStore access |
| permission_handler | Runtime permissions |
| file_picker | File and folder selection |
| window_manager | Desktop window management |
| url_launcher | Opening external links |
| ffmpeg_kit_flutter_new | Media processing |
| http | Network requests |
| device_info_plus | Device information |
| rxdart | Reactive stream extensions |
| html | HTML parsing |

---

## License

MIT License -- see [LICENSE.txt](LICENSE.txt) for details.
