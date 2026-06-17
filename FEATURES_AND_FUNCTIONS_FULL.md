# PlayerVf Full Features And Functions Documentation

This file documents the PlayerVf project as a full feature and function map. It explains what the app does, which files own each area, and what the major classes/functions are responsible for.

## 1. App Summary

PlayerVf is a cross-platform Flutter music and video player. It supports local music scanning, audio playback, video playback, playlists, favorites, lyrics, audio effects, YouTube Music search/stream/download, local network sharing, Wi-Fi Direct sharing, metadata editing, cover art extraction, and deep appearance customization.

The app is built with Flutter and uses:

- `media_kit`, `media_kit_video`, and platform video libraries for playback.
- `just_audio`, `audio_service`, and `smtc_windows` for audio/media session integration.
- `provider` for app state.
- `shared_preferences` for settings and saved state.
- `file_picker`, `path_provider`, and platform APIs for local files.
- `on_audio_query` and permissions for Android media scanning.
- Python helpers for YouTube Music, downloads, thumbnails, subtitles, and tagging.

## 2. Main User Features

### Local Library

- Scan music folders from configured source paths.
- Import music from selected folders.
- Import web folder music when running on web.
- Keep a remembered library snapshot so songs, favorites, stats, and metadata survive app restarts.
- Read metadata from ID3, MP4, FLAC, APE, Android media store hints, and fallback filenames.
- Extract cover art from files or sidecar assets.
- Track duration, title, artist, album, genre, file path, cover path, play count, last played, date added, and favorite state.
- Clear cached library data.

### Playback

- Play, pause, toggle play/pause.
- Next track.
- Previous track.
- Restart current track.
- Previous-or-restart shortcut behavior.
- Seek to a position.
- Seek forward/backward from keyboard shortcuts.
- Volume control and mute behavior.
- Smooth volume changes.
- Smooth track open/play/pause transitions.
- Repeat modes: repeat all, repeat one, repeat off-style cycling.
- Shuffle mode.
- Queue playback.
- Streaming playback from YouTube results.
- Resume playback position after app restart.
- Configurable gap between songs.

### Audio Effects

- Enable/disable effects globally.
- Enable/disable equalizer.
- Pitch control.
- Playback speed control.
- Reverb control.
- Equalizer band control.
- Equalizer presets.
- Per-song effect settings.
- Global effect settings.
- Reset equalizer.
- Reset all audio effects.
- Native Windows audio filter support when available.
- MPV/libavfilter fallback effects.

### Video

- Detect whether current media is a video.
- Video controller initialization.
- Local video playback.
- YouTube video streaming and playback.
- Downloaded YouTube video manifest support.
- Switch local downloaded video quality.
- Switch YouTube stream quality.
- Fullscreen video player.
- Auto-hide fullscreen controls.
- Subtitle loading from file.
- Subtitle loading from URL.
- Auto sidecar subtitle detection.
- Disable subtitles.
- Double-tap fullscreen option.
- Optional live video background/cover behavior.

### Lyrics

- Load sidecar lyrics for the current track.
- Parse LRC-style timed lyrics.
- Parse plain lyrics.
- Find active lyric line based on playback position.
- Search lyrics online.
- Search lyrics with custom title/artist/album/duration.
- Show search result choices.
- Save selected online lyrics locally.
- Edit current lyrics.
- Open lyrics from file.
- Fullscreen lyrics view.
- Auto-scroll timed lyrics.

### Playlists And Favorites

- Favorite/unfavorite tracks.
- Favorites page.
- Create custom playlist.
- Rename playlist.
- Delete playlist.
- Add song to playlist.
- Remove song from playlist.
- Play playlist.
- Playlist detail page.
- System playlists:
  - Favorites.
  - Recent/recently played.
  - Most listened.
  - Daily mix.
  - Early listened/older listening history.
- Playlist artwork collage from member songs.

### Queue

- Start a queue from a list.
- Play a specific track from a queue.
- Add a song to the active queue.
- Remove a song from queue.
- Move queue item.
- Resolve queue IDs into music objects.
- Maintain shuffled queue IDs separately from normal queue IDs.
- Sync queue when library changes.

### YouTube Music

- Search YouTube Music by query.
- Filter result types.
- Stream a result without downloading.
- Download audio.
- Download video.
- Select video quality.
- Download subtitles.
- Download subtitles only.
- Choose automatic or manual subtitle languages.
- Cache stream URLs.
- Warm stream cache for upcoming results.
- Resolve and create download directory.
- Mark already downloaded audio/video/subtitles.
- Use Android method channel/native Python helper on Android.
- Use desktop Python process on desktop.
- Friendly error messages when Python/dependencies fail.

### Sharing

- Start a local share server.
- Share current song or full library.
- Stop sharing.
- Discover share servers on local network.
- Fetch remote manifest.
- Download remote tracks.
- Pause transfer.
- Resume transfer.
- Cancel transfer.
- Show transfer progress, speed, endpoints, and status.
- Save synced files in a sync directory.
- Avoid duplicate downloaded files by checking existing names/sizes.
- Optional library backup before importing shared files.
- Android Wi-Fi Direct discovery/connect/trust support.

### Metadata And Covers

- Show full track info.
- Edit title, artist, album, genre-like metadata where supported.
- Pick custom cover art.
- Update cover path.
- MusicBrainz automatic tag lookup.
- MusicBrainz manual search.
- Score possible tag matches.
- Apply selected MusicBrainz result.
- Use cover palette colors for player/video backgrounds.

### Appearance And Settings

- Dark/light/system theme mode.
- Theme presets:
  - Material.
  - Graphite.
  - Classic.
  - Fox.
  - Anime.
  - Azure.
  - Cosmic.
  - Sunset.
  - Midnight.
- Accent color picker.
- RGB color sliders.
- Glass effect intensity.
- Border radius.
- Font size.
- Card size.
- Card margins.
- Manual or automatic card count.
- Navigation position: top, bottom, left, right.
- View mode: card or list.
- Particle effects:
  - None.
  - Sakura.
  - Snow.
  - Stars.
  - Bubbles.
  - Rain.
- Performance modes:
  - Auto.
  - Quality.
  - Balanced.
  - Battery saver.
  - Max performance.
- Audio decoder mode: auto/software/hardware.
- Video decoder mode: auto/software/hardware.
- YouTube download path.
- Music source paths.
- Share sync backup toggle.

### Desktop And Keyboard

- Desktop fullscreen toggle.
- Keyboard shortcuts for play/pause, next, previous/restart, seek, volume, mute, search, and fullscreen-related behavior.
- Windows keyboard assertion guard.
- Windows System Media Transport Controls metadata and timeline.
- Smooth scroll behavior for desktop/web.

## 3. File Map

### Root Files

- `pubspec.yaml`: Flutter package config, dependencies, assets, app icon config.
- `README.md`: short public project description.
- `analysis_options.yaml`: lint configuration.
- `LICENSE.txt`: MIT license.

### Assets

- `assets/logo.png`: app logo.
- `assets/images/app_ico.png`: app icon asset.
- `assets/images/play.png`, `pause.png`, `back.png`, `next.png`: playback image buttons.
- `assets/images/play-to-pause/*`: animation frames for play-to-pause.
- `assets/images/pause-to-play/*`: animation frames for pause-to-play.

### Main Flutter App

- `lib/main.dart`: app entrypoint, providers, theming, navigation, shortcuts, mini player, global player overlay.

### Models

- `lib/models/music_model.dart`: `Music`.
- `lib/models/playlist_model.dart`: `Playlist`.
- `lib/models/settings_model.dart`: settings enums and `SettingsModel`.
- `lib/models/lyrics_model.dart`: `LyricLine`, `LyricsDocument`.
- `lib/models/cover_model.dart`: `Cover`.
- `lib/models/page_state.dart`: page selection enum/state.

### Pages

- `lib/pages/home_screen.dart`: home/library smart playlist page.
- `lib/pages/favorite_page.dart`: favorites list/grid.
- `lib/pages/playlist_page.dart`: playlist overview.
- `lib/pages/playlist_detail_page.dart`: songs inside one playlist.
- `lib/pages/player_page.dart`: full audio player and lyrics.
- `lib/pages/video_page.dart`: video player and fullscreen video.
- `lib/pages/youtube_music_page.dart`: YouTube Music search/stream/download UI.
- `lib/pages/share_page.dart`: local sharing/sync UI.
- `lib/pages/settings_screen.dart`: settings page.
- `lib/pages/appearance_screen.dart`: appearance customization page.

### Services

- `lib/services/music_service.dart`: central player/library/state service.
- `lib/services/music_scanner_service.dart`: scans files and media store.
- `lib/services/id3_parser.dart`: parses audio/video metadata.
- `lib/services/cover_extractor.dart`: extracts embedded or asset covers.
- `lib/services/cover_color_service.dart`: creates color palettes from covers.
- `lib/services/youtube_music_service.dart`: Flutter-to-Python bridge for YouTube.
- `lib/services/musicbrainz_tag_service.dart`: MusicBrainz lookup/scoring.
- `lib/services/local_share_service.dart`: local HTTP sharing/discovery/download.
- `lib/services/wifi_direct_service.dart`: Android Wi-Fi Direct helper.
- `lib/services/player_audio_handler.dart`: background/media controls.
- `lib/services/player_controller.dart`: thin playback command wrappers.
- `lib/services/performance_policy.dart`: performance capability policy.
- `lib/services/responsive.dart`: responsive sizing helpers.
- `lib/services/web_folder_picker.dart`: conditional web folder picker entry.
- `lib/services/web_folder_picker_web.dart`: web folder import logic.
- `lib/services/web_folder_picker_stub.dart`: non-web stub.

### Widgets

- `lib/widgets/music_card.dart`: song card/list UI and track actions.
- `lib/widgets/playlist_card.dart`: playlist card UI.
- `lib/widgets/small_playlist_card.dart`: compact playlist card.
- `lib/widgets/playback_progress_control.dart`: progress bar/scrubber.
- `lib/widgets/audio_effects_menu.dart`: audio effects sheet.
- `lib/widgets/cover_art_texture.dart`: cover art renderer.
- `lib/widgets/glass_container.dart`: glass effect container.
- `lib/widgets/particle_system.dart`: animated particle background.
- `lib/widgets/stable_video_surface.dart`: video surface wrapper.
- `lib/widgets/settings_drawer.dart`: settings drawer.
- `lib/widgets/fade_in_up_animation.dart`: entrance animation.
- `lib/widgets/show_up_control.dart`: show/hide wrapper.
- `lib/widgets/page_switch_button.dart`: navigation button.

### Python

- `lib/python/api.py`: desktop Python backend for YouTube Music, downloads, video/subtitle handling, metadata and thumbnails.
- `android/app/src/main/python/mymodule.py`: Android Python backend for YouTube Music search/download/stream.
- `android/app/src/main/python/api.py`: Android helper API file.
- `lib/python/requirements.txt`: Python package requirements.

## 4. Main Application Classes And Functions

### `main()` in `lib/main.dart`

Starts Flutter, initializes `media_kit`, configures desktop window behavior, installs a Windows keyboard assertion guard, and launches `MyApp`.

### `MyApp`

Top-level app widget. It creates and provides:

- `SettingsModel`.
- `MusicService`.

It also builds the Material app theme based on:

- theme mode,
- theme preset,
- accent color,
- glass intensity,
- card radius,
- platform brightness.

### `_SmoothScrollBehavior`

Custom scroll behavior that allows touch, mouse, stylus, and trackpad dragging. This makes desktop/web scrolling feel natural.

### `MainNavigationScreen`

Main shell of the app. It owns:

- selected tab index,
- player overlay visibility,
- global search state,
- keyboard shortcuts,
- mini player,
- navigation dock,
- top app bar,
- main content area.

Important functions:

- `_screens`: returns Home, Favorites, Playlists, YouTube Music, and Share pages.
- `_onDestinationSelected`: changes current page.
- `_togglePlayer`: opens/closes the full player overlay.
- `_closePlayer`: hides full player.
- `_openPlayer`: shows full player.
- `_allowPlayPauseShortcut`: prevents shortcuts while typing.
- `_seekRelative`: seeks current playback by configured seconds.
- `_changeVolume`: raises/lowers volume.
- `_toggleMute`: mutes/restores volume.
- `_toggleDesktopFullscreen`: switches desktop fullscreen.
- `_isTypingInEditable`: detects if focus is inside text input.
- `_buildMicaBackground`: builds animated/glass background using cover colors and particles.
- `_effectiveTopMargin`: calculates layout spacing from settings.
- `_buildTopAppBar`: builds top controls/search/settings.
- `_buildNavigationDock`: builds nav UI based on nav position.
- `_buildNavItem`: builds each navigation icon.
- `_buildMainContentArea`: places selected screen and overlay spacing.
- `_buildSearchBar`: builds global search field.
- `_buildMiniPlayer`: builds bottom/side mini player.

### `_MiniPlayPauseButton`

Small play/pause control in the mini player. It uses optimistic UI state so the button changes immediately while playback command completes.

## 5. Models

### `Music`

Represents one track or media item.

Fields:

- `id`: stable identifier.
- `title`: display title.
- `artist`: display artist.
- `album`: album name.
- `filePath`: local path, URL, blob path, or streaming path.
- `coverPath`: cover image path/URL.
- `genre`: genre text.
- `duration`: optional playback duration.
- `isFavorite`: favorite state.
- `playCount`: number of plays.
- `lastPlayed`: last playback timestamp.
- `dateAdded`: library add timestamp.

Functions:

- `toJson`: serializes track data.
- `fromJson`: restores track data.
- `fromBase`: copies a base music object while replacing stats.

### `Playlist`

Represents a user or system playlist.

Fields:

- `id`.
- `name`.
- `musicIds`.
- `createdAt`.
- `updatedAt`.

Functions:

- `copyWith`: creates modified copy.
- `toJson`: serializes playlist.
- `fromJson`: restores playlist.

### `SettingsModel`

Persistent settings model backed by `SharedPreferences`.

Enums:

- `ViewMode`: `card`, `list`.
- `NavPosition`: `top`, `bottom`, `left`, `right`.
- `ThemePreset`: visual preset set.
- `ParticleEffect`: particle animation type.
- `DecoderMode`: `auto`, `software`, `hardware`.
- `PerformanceMode`: `auto`, `quality`, `balanced`, `batterySaver`, `maxPerformance`.

Main fields:

- music paths,
- YouTube download path,
- card size/margins/count,
- theme mode,
- view mode,
- nav position,
- theme preset,
- particle effect,
- font size,
- border radius,
- glass effect,
- accent color,
- seek step seconds,
- song gap,
- video background/live cover/fullscreen settings,
- decoder modes,
- performance mode,
- share backup setting.

Important functions:

- `loadSettings`: loads persisted preferences.
- `_applyThemeDefaults`: updates accent/particles when choosing preset.
- `setThemePreset`: saves theme preset.
- `setParticleEffect`: saves particle effect and changes preset to classic.
- `setNavPosition`: saves navigation position.
- `setFontSize`: saves font size.
- `setBorderRadius`: saves border radius.
- `setGlassEffect`: saves glass intensity.
- `setAccentColor`: saves custom accent and moves preset to classic.
- `setSeekStepSeconds`: saves seek step.
- `setSongGapMs`: saves gap between songs.
- `setViewMode`: saves card/list mode.
- `setThemeMode`: saves light/dark/system mode.
- `setCardSize`: saves card size.
- `setCardMargins`: saves spacing.
- `setTopMargin`: saves top margin.
- `setCardCount`: saves manual grid count.
- `setUseAutoCardCount`: toggles automatic grid count.
- `setPlayVideoBackground`: toggles video background.
- `setVideoCoverShowLive`: toggles live video cover.
- `setVideoDoubleTapFullscreen`: toggles double-tap fullscreen.
- `setAudioDecoderMode`: saves audio decoder preference.
- `setVideoDecoderMode`: saves video decoder preference.
- `setPerformanceMode`: saves performance profile.
- `setShareSyncBackupsEnabled`: saves share backup preference.
- `addMusicPath`: adds a source folder.
- `setYoutubeMusicDownloadPath`: saves YouTube downloads folder and includes it in library paths.
- `removeMusicPath`: removes a source path.
- `clearAllPaths`: clears source paths.
- `_saveSettings`: writes all settings to preferences.

### `LyricsDocument`

Represents parsed lyrics.

Fields:

- `rawText`: original lyrics.
- `lines`: parsed `LyricLine` entries.
- `source`: where lyrics came from.

Functions:

- `hasTimedLines`: true when any line has timestamp.
- `plainText`: lyrics without timestamps.
- `activeIndexAt`: returns the active timed lyric line for a playback position.
- `parse`: parses LRC/plain lyrics.
- `_parseTimestamp`: turns `[mm:ss.xx]` into `Duration`.

## 6. MusicService: Central Playback And Library Service

File: `lib/services/music_service.dart`

`MusicService` is the biggest and most important service. It owns most player state and connects UI, media backends, playlists, lyrics, audio effects, video, storage, and queue behavior.

### Main State

- `_musicList`: local and imported library.
- `_currentIndex`: selected track index.
- `_isPlaying`: local playback state.
- `_player`: primary media player.
- `_videoControllerReady`: video state.
- `_volume`: user volume.
- `_position`, `_duration`: playback progress.
- `_activeQueueIds`: normal queue.
- `_shuffledQueueIds`: shuffled queue.
- `_isShuffle`: shuffle mode.
- `_playlists`: custom playlists.
- `_isRepeatOne`, `_isRepeatAll`: repeat state.
- `_rememberPlayback`: resume setting.
- `_streamingMusic`: currently streamed YouTube item.
- audio effect fields: pitch, speed, reverb, EQ, presets, song-specific settings.
- subtitle and lyric state.

### Initialization Functions

- `_initVideoController`: creates video-capable player state.
- `_bindPlayer`: wires position/duration/playing streams.
- `_ensureVideoControllerForCurrentTrack`: prepares video player for current video.
- `_initializeAsync`: loads settings, stats, favorites, library snapshot, decoder settings, and playback state.
- `_refreshLibraryAfterFirstFrame`: refreshes library after UI is ready.
- `_initPlayer`: initializes player/audio handler callbacks.

### Public Getters

- `musicList`: all tracks.
- `currentMusic`: current track.
- `currentIndex`: current library index.
- `isPlaying`: playback state.
- `position`: current position.
- `duration`: current duration.
- `volume`: current volume.
- `isLoadingSystemMusic`: scanner loading flag.
- `systemMusicCount`: count found during scan.
- `playlists`: custom playlists.
- `isShuffle`: shuffle state.
- `videoControllerReady`: video ready flag.
- `hasVideoTrack`: whether current track is video.
- `isCurrentMediaVideo`: detects current track type.
- `isRepeatOne`, `isRepeatAll`: repeat flags.
- `isEffectsEnabled`, `isEqualizerEnabled`: audio effect flags.
- `currentPreset`: active equalizer preset.
- `pitch`, `speed`, `reverb`: audio controls.
- `useSongSpecificSettings`: per-song effects toggle.
- `isInitialized`: initialization flag.
- `rememberPlayback`: resume playback setting.
- `queueMusicList`: active queue as music objects.
- `currentQueuePosition`: index inside active queue.
- `currentEqBandValues`: active equalizer band values.
- `favoriteMusicList`: favorites.
- `systemPlaylists`: generated playlists.
- `allPlaylists`: system plus custom playlists.

### Audio Effect Functions

- `setEffectsEnabled`: enables/disables audio effects.
- `setEqualizerEnabled`: enables/disables EQ.
- `setUseSongSpecificSettings`: chooses per-song or global effects.
- `setPitch`: updates pitch.
- `setSpeed`: updates speed.
- `setReverb`: updates reverb.
- `setEqualizerBand`: saves EQ band value.
- `previewEqualizerBand`: previews EQ value while dragging.
- `_normalizeEqGain`: clamps EQ gain.
- `_normalizeEqValues`: cleans EQ list values.
- `setEqualizerPreset`: applies preset values.
- `resetEqualizer`: resets EQ bands.
- `_applyFlatEqualizerPreset`: applies flat EQ.
- `resetAudioEffects`: resets all effect controls.
- `_scheduleUpdate`: debounces effect application.
- `_applyScheduledEffects`: applies pending effects.
- `_applyAudioEffects`: sends filter settings to active backend.
- `_buildAudioFilter`: builds filter chain text.
- `_buildEqualizerFilterParts`: builds EQ filter pieces.
- `_buildFallbackEqVolumeFactor`: protects volume from EQ clipping.
- `_applyNativeWindowsAudioEffects`: applies Windows native player filter.
- `_setNativeAudioFilter`: sends filter to native backend.
- `_mpvLavfiAudioFilter`: converts filter for MPV.
- `_setNativeAudioFilterByCommand`: sends command-based filter.
- `_setNativePlayerProperty`: sets native player property.
- `_getNativePlayerProperty`: reads native player property.

### Decoder And Subtitle Functions

- `setDecoderModes`: saves and applies decoder mode preferences.
- `_loadDecoderSettingsAsync`: loads decoder settings.
- `_applyDecoderSettings`: configures player decoding.
- `_videoHwdecValue`: converts setting into media_kit/native value.
- `loadSubtitleFile`: loads external subtitle file.
- `loadSubtitleUrl`: loads remote subtitle URL.
- `disableSubtitles`: turns subtitles off.
- `_applySidecarSubtitleIfAvailable`: auto-loads sidecar subtitle next to video.
- `_subtitleSidecarCandidates`: builds possible subtitle filenames.

### Lyrics Functions

- `loadLyricsForCurrent`: returns lyrics text for current track.
- `loadLyricsDocumentForCurrent`: returns parsed lyrics document.
- `saveLyricsForCurrent`: saves manual lyrics.
- `searchLyricsForCurrentOnline`: searches lyrics with track metadata.
- `searchLyricsForCurrentWithCustomParameters`: searches with user-provided metadata.
- `searchLyricsResultsForCurrent`: returns multiple online lyrics results.
- `saveLyricsResultForCurrent`: saves a selected online result.
- `editableLyricsForCurrent`: returns editable text.
- `_manualLyricsPathForMusic`: path for LRC lyrics.
- `_manualPlainLyricsPathForMusic`: path for plain lyrics.
- `_lyricsOwnerKey`: stable key for lyrics ownership.
- `_isCurrentLyricsOwner`: avoids applying stale lyric results to a changed track.
- `_safeLyricsFileToken`: safe filename part for lyrics.
- `_tryFetchLyricsOnline`: tries online lyric lookup.
- `_fetchLyricsOnlineForQueries`: loops through possible queries.
- `_fetchLyricsResultsOnlineForQueries`: returns scored lyric matches.
- `_lyricsQueriesForMusic`: builds title/artist/album query variants.
- `_manualLyricsQueries`: builds query variants from manual input.
- `_fetchLrclibExact`: exact LRCLIB fetch.
- `_fetchLrclibById`: fetch by LRCLIB ID.
- `_searchLrclib`: search LRCLIB.
- `_getLrclibJson`: HTTP JSON helper.
- `_scoreLrclibResult`: scores lyric match quality.
- `_lyricsResultMatchesQuery`: validates match.
- `_lyricsResultHasRequestedName`: checks names.
- `_sameLyricsToken`: compares normalized tokens.
- `_normalizeLyricsToken`: normalizes text for matching.
- `_cleanLyricsSearchText`: removes noisy text.
- `_saveFetchedLyricsForMusic`: writes fetched lyrics to disk.
- `_lyricsResultMatchesMusicName`: checks result against track.
- `_lyricsSidecarCandidates`: builds `.lrc`/`.txt` sidecar paths.
- `_lyricsCandidateMatchesMusic`: checks sidecar belongs to track.

### Playback Functions

- `play`: starts playback of current/selected track.
- `_playStreamingCurrent`: starts streaming item.
- `togglePlayPause`: toggles playback.
- `_runPlaybackCommand`: serializes playback commands.
- `_togglePlayPauseInternal`: internal toggle logic.
- `seekTo`: seeks player.
- `setVolume`: updates volume.
- `_smoothSetUserVolume`: fades user volume.
- `next`: public next command.
- `_nextInternal`: moves to next queue/library item.
- `previous`: public previous command.
- `previousTrack`: previous track command.
- `restartCurrentTrack`: seeks to zero.
- `previousOrRestartShortcut`: restarts or goes previous depending on current position.
- `_previousOrRestartShortcutInternal`: internal previous/restart logic.
- `_previousInternal`: moves to previous queue/library item.
- `toggleShuffle`: toggles shuffle and rebuilds order.
- `toggleRepeatMode`: cycles repeat behavior.
- `_handleTrackCompleted`: handles end-of-track based on repeat/queue.
- `_handleBackendCompleted`: backend completion callback.
- `_playbackOrderIds`: returns normal/shuffled order.
- `_resolveMusicIds`: converts IDs to track objects.
- `_ensureQueueInitialized`: creates queue if missing.
- `_rebuildShuffledQueue`: creates shuffled order.
- `_moveInQueue`: moves current position forward/backward.

### Media Backend Functions

- `_cacheCurrentTrackDuration`: stores known duration.
- `_setPlayerVolume`: sets a player's volume.
- `_effectiveBackendVolume`: converts UI volume to backend volume.
- `_shouldUseNativeWindowsAudio`: decides Windows native backend use.
- `setSongGapDuration`: saves and applies track gap.
- `_waitForSongGapIfNeeded`: waits between songs.
- `_setPlayerVolumeInternal`: sets backend volume without feedback loops.
- `_setOutputVolume`: applies output volume.
- `_setBackendVolume`: updates player/native volume.
- `_fadeBackendVolume`: fades volume.
- `_smoothOpenAndPlay`: opens new media with smooth transition.
- `_setDurationForOpeningTrack`: sets duration during loading.
- `_smoothPlayCurrentBackend`: smooth play.
- `_smoothPauseCurrentBackend`: smooth pause.
- `_setLocalPlayingState`: updates local flag.
- `_preparePlayerForTrack`: prepares backend for selected track.
- `_applyResumePositionOnPlayerIfNeeded`: seeks to saved resume point.
- `_openTrackMedia`: opens file/URL/media source.
- `_scheduleUpdateNow`: updates system now-playing.
- `_clearNowPlaying`: clears media session.
- `_playCurrentBackend`: backend play.
- `_pauseCurrentBackend`: backend pause.
- `_seekCurrentBackend`: backend seek.
- `_syncExternalPlaybackState`: updates media session state.

### Library Functions

- `loadSystemMusic`: scans configured paths/device media.
- `importWebFolderMusic`: imports browser folder tracks.
- `importSharedMusicFiles`: imports tracks downloaded from sharing.
- `_backupLibraryBeforeShareImport`: writes safety backup before shared import.
- `clearCache`: clears cached library.
- `deleteMusic`: removes track from library.
- `updateMusicMetadata`: updates title/artist/album values.
- `updateMusicCover`: updates cover path.
- `_loadLibrarySnapshotAsync`: restores cached library.
- `_saveLibrarySnapshot`: persists current library.
- `_mergeRememberedTrackState`: merges stats/favorites into rescanned tracks.
- `_shouldReplaceScannedTrack`: decides whether scanned metadata should replace old track.
- `_isTransientWebPath`: detects browser blob URLs.
- `_collapseDownloadedVideoQualitySets`: hides duplicate video quality files.
- `_isNonPrimaryDownloadedQuality`: detects secondary downloaded quality files.

### Playlist And Favorite Functions

- `_refreshSystemPlaylistsInternal`: updates smart playlists.
- `refreshSystemPlaylists`: public refresh.
- `_generateDailyMix`: creates daily mix list.
- `createPlaylist`: creates custom playlist.
- `renamePlaylist`: renames playlist.
- `deletePlaylist`: removes playlist.
- `addMusicToPlaylist`: adds song.
- `removeMusicFromPlaylist`: removes song.
- `playPlaylist`: starts playlist playback.
- `playMusicFromQueue`: plays chosen track from given queue.
- `playStreamingMusic`: starts YouTube streaming music item.
- `replaceStreamingMusic`: replaces current stream with new stream.
- `startQueue`: initializes queue from tracks.
- `addToQueue`: appends song to queue.
- `removeFromQueue`: removes song from queue.
- `moveQueueItem`: reorders queue.
- `getMusicListForPlaylist`: resolves playlist songs.
- `toggleFavorite`: toggles favorite state and saves it.
- `isFavorite`: checks favorite state.
- `_savePlaylists`: persists custom playlists.
- `_loadFavoritesAsync`: restores favorites.
- `_saveStats`: persists play counts and dates.
- `_loadStatsAsync`: restores play stats.

### Persistence And Lifecycle Functions

- `setRememberPlayback`: toggles resume playback.
- `savePlaybackSnapshotNow`: saves current playback position immediately.
- `_loadSettingsAsync`: loads service settings.
- `_saveDebounced`: debounced library/stats save.
- `_savePlaybackDebounced`: debounced playback save.
- `_saveAudioEffectsSettings`: saves audio effects.
- `_savePlaybackState`: saves current track/position.
- `_applyResumePositionIfNeeded`: applies saved resume position.
- `didChangeAppLifecycleState`: saves state on pause/inactive.
- `_restorePlaybackStateIfNeeded`: restores last track and position.
- `_clearResumeState`: clears resume data.
- `dispose`: disposes timers/players/listeners.

## 7. Pages

### `HomeScreen`

Shows library entry points and playlist-style cards.

Functions:

- `build`: renders page.
- `_buildResponsiveLayout`: chooses grid/list layout by width.
- `_buildSquarePlaylistCard`: creates a large playlist tile.
- `_buildPlaylistCollage`: builds cover collage.
- `_buildAddPlaylistSquare`: add playlist tile.
- `_showCreatePlaylistDialog`: opens new playlist dialog.
- `_buildEmptyState`: shown when no music exists.
- `_calculateAutoCrossAxisCount`: calculates grid count from width/card size.

### `FavoritePage`

Shows favorite songs.

Functions:

- `build`: renders favorites with search filtering.
- `_calculateAdaptiveCrossAxisCount`: responsive grid count.

### `PlaylistPage`

Shows system and custom playlists.

Functions:

- `build`: renders playlist overview.
- `_buildEmptyState`: empty playlist message/action.
- `_calculateAdaptiveCrossAxisCount`: responsive card grid.
- `_showCreatePlaylistDialog`: creates playlist.

### `PlaylistDetailPage`

Shows tracks inside one playlist.

Functions:

- `build`: renders playlist details and songs.
- `_openPlayerFromDetail`: opens player overlay.
- `_buildPlaylistCollage`: cover collage for playlist header.
- `_calculateCrossAxisCount`: grid count.
- `_showEditPlaylistDialog`: rename/delete/edit playlist.

### `PlayerPage`

Full audio player.

Functions:

- `didChangeDependencies`: loads cover palette when track changes.
- `_syncPalette`: refreshes palette future.
- `build`: renders player page.
- `_buildTopBar`: close/settings/top controls.
- `_buildBackground`: cover-based background.
- `_buildHeroArtwork`: large cover art.
- `_buildMetadata`: title/artist/album text.
- `_buildControlsSection`: play/pause/next/previous/progress/volume/effects.
- `_buildQuickQueue`: compact queue preview.
- `_showMoreOptions`: player menu.
- `_showAddCurrentTrackToPlaylistDialog`: add current track.
- `_showCurrentTrackDetails`: track info dialog.
- `_buildTrackDetailRow`: row in details dialog.
- `_formatTrackDuration`: duration text.
- `_showPlayerSnack`: snackbar helper.
- `_showQueueSheet`: full queue sheet.
- `_showLyricsSheet`: lyrics bottom sheet.
- `_pickLyricsFile`: file picker for lyrics.

Lyrics subcomponents:

- `_LyricsSheetContent`: lyrics UI in bottom sheet.
- `_reloadLyricsForCurrentTrack`: reloads lyrics when track changes.
- `_buildTimedLyrics`: timed lyric list.
- `_scrollActiveLineIntoView`: auto-scrolls current lyric.
- `_openLyricsFile`: choose lyrics file.
- `_openFullscreenLyrics`: opens fullscreen lyrics.
- `_searchLyrics`: online search.
- `_searchLyricsWithCustomInput`: manual parameter search.
- `_showLyricsSearchResults`: choice dialog.
- `_formatLyricsDuration`: result duration text.
- `_showLyricsSearchMessage`: found/not found feedback.
- `_editLyrics`: edit and save lyrics.
- `_FullscreenLyricsPage`: fullscreen lyrics view.
- `_jumpLyricsToTop`: scrolls lyrics top.
- `_buildPlainLyrics`: plain lyrics UI.
- `_buildEmptyLyrics`: no lyrics UI.

### `VideoPage`

Full video player.

Functions:

- `didChangeDependencies`: syncs palette and video details.
- `_syncPalette`: refreshes video palette.
- `_extractYoutubeVideoId`: finds YouTube video id from current track.
- `_syncYoutubeDetails`: loads stream qualities/subtitles.
- `_syncLocalVideoManifest`: loads downloaded-video manifest.
- `_looksLikeLocalVideo`: checks extension/path.
- `_loadLocalVideoManifest`: loads local quality/subtitle manifest.
- `_findLocalVideoManifest`: finds manifest near file.
- `_loadYoutubeDetails`: loads YouTube stream metadata.
- `_autoLoadYoutubeSubtitle`: selects default subtitle.
- `_changeYoutubeQuality`: changes YouTube stream quality.
- `_changeLocalVideoQuality`: switches downloaded local quality file.
- `_videoSurfaceIdentity`: creates stable surface identity.
- `build`: renders video page.
- `_buildTopBar`: top controls.
- `_buildBackground`: video background.
- `_buildHeroVideo`: main video surface.
- `_buildQualityTransitionOverlay`: loading overlay during quality change.
- `_openFullscreenVideo`: pushes fullscreen video route.
- `_seekBy`: seeks video.
- `_buildMetadata`: video metadata.
- `_buildControlsSection`: playback controls.
- `_buildYoutubeVideoTools`: quality/subtitle tools.
- `_buildQuickQueue`: queue preview.
- `_showMoreOptions`: options sheet.
- `_showQualitySheet`: quality picker.
- `_showSubtitleSheet`: subtitle picker.
- `_pickSubtitleFileFor`: choose local subtitle.
- `_showQueueSheet`: full queue sheet.

Fullscreen video:

- `_FullscreenVideoPage`: fullscreen route.
- `_showOverlay`: shows controls.
- `_scheduleOverlayHide`: hides controls after delay.
- `_buildControls`: fullscreen controls.
- `_pickSubtitleFile`: choose subtitle in fullscreen.
- `_FullscreenToolButton`: reusable fullscreen icon button.
- `_SmoothPlayPauseButton`: optimistic play/pause button.

### `YoutubeMusicPage`

Searches, streams, and downloads YouTube Music items.

Functions:

- `_runBridgeSmokeTest`: verifies Python/channel bridge.
- `_search`: searches YouTube Music.
- `_download`: handles download request.
- `_chooseDownloadOptions`: dialog for audio/video/subtitles/quality/languages.
- `_subtitleKey`: stable subtitle key.
- `_loadDownloadedYoutubeSet`: checks existing downloads for one result.
- `_refreshDownloadedCache`: refreshes downloaded markers.
- `_readVideoDownloadMarks`: detects downloaded video qualities/subtitles.
- `_readAudioDownloadMarks`: detects downloaded audio.
- `_downloadMarkText`: display text for downloaded state.
- `_stream`: streams a result.
- `build`: renders page.
- `_buildHeader`: title/status.
- `_buildSearchPanel`: query/filter controls.
- `_buildMessage`: status/error message.
- `_buildEmptyState`: empty search state.
- `_buildResultTile`: result row/card.
- `_resultKey`: stable key for result cache.
- `wantKeepAlive`: keeps search page alive between tabs.

### `SharePage`

UI for local sharing and syncing.

Functions:

- `initState`: creates services.
- `dispose`: stops server/listeners.
- `_startSharing`: starts local share server.
- `_stopSharing`: stops server.
- `_autoFindDevices`: scans local/Wi-Fi devices.
- `_connectToDevice`: fetches remote manifest.
- `_syncTracks`: downloads selected tracks.
- `_pauseTransfer`: pauses active transfer.
- `_resumeTransfer`: resumes active transfer.
- `_cancelTransfer`: cancels transfer.
- `build`: renders page.
- `_buildHostCard`: share-current/full-library host controls.
- `_buildConnectCard`: discovery/connect controls.
- `_sectionTitle`: section header.
- `_trackTile`: remote track row.
- `_deviceTile`: device row.
- `_statusPill`: small status indicator.
- `_buildTransferControls`: pause/resume/cancel controls.
- `_buildTransferFlowCard`: progress visualization.
- `_transferEndpoint`: source/target transfer display.
- `_buildMessage`: empty/error/status message.
- `_formatBytes`: byte count text.

### `SettingsScreen`

Settings for scanning, paths, video, decoder, performance, cache, and subtitles.

Functions:

- `build`: renders settings.
- `_updateAllMusic`: rescans library.
- `_showClearCacheDialog`: confirms cache clear.
- `_buildSectionTitle`: section label.
- `_buildGlassSettingCard`: styled settings group.
- `_buildSongGapSetting`: song gap control.
- `_buildPathTile`: source path row.
- `_addPath`: add music folder/import folder.
- `_setYoutubeDownloadPath`: choose download folder.
- `_useDefaultYoutubeDownloadPath`: reset to default downloads path.
- `_showWebFolderMessage`: tells user about web folder import.
- `_showFolderImportMessage`: import result message.
- `_buildVideoSettingsCard`: video toggles and subtitle option.
- `_buildDecoderModeRow`: decoder choices.
- `_buildPerformanceModeRow`: performance choices.
- `_setAudioDecoderMode`: save audio decoder.
- `_setVideoDecoderMode`: save video decoder.
- `_pickSubtitleFile`: choose subtitle for current video.

### `AppearanceScreen`

Settings for theme and layout.

Functions:

- `build`: renders appearance page.
- `_buildSectionTitle`: section label.
- `_buildGlassCard`: styled group.
- `_buildSwitchRow`: switch setting row.
- `_buildPresetButton`: theme preset button.
- `_buildParticleButton`: particle option.
- `_buildParticleWarning`: performance warning.
- `_buildAccentColorPicker`: color picker UI.
- `_buildColorChannelSlider`: RGB sliders.
- `_buildColorButton`: preset color button.
- `_buildNavPosButton`: navigation location button.
- `_buildSliderRow`: slider setting row.
- `_buildThemeButton`: light/dark/system button.
- `_buildViewModeButton`: card/list button.
- `_ReleaseSlider`: slider that previews value while dragging.

## 8. Services

### `MusicScannerService`

Scans folders and media sources into `Music` objects.

Responsibilities:

- Locate audio/video files.
- Request/use permissions on mobile.
- Read Android media store hints.
- Parse metadata with `ID3Parser`.
- Extract cover with `CoverExtractor`.
- Normalize paths and IDs.
- Avoid duplicates.
- Support common audio/video formats.

### `ID3Parser`

Reads metadata from files.

Important functions:

- `parseTagsFromFile`: main metadata entry.
- `_parseMp3Tags`: parses ID3v2 MP3 tags.
- `_parseManualId3Cover`: extracts MP3 embedded cover.
- `_skipId3Description`: skips APIC description fields.
- `_syncSafeIntAt`: reads ID3 sync-safe integers.
- `_parseId3v1`: parses old ID3v1 tail tags.
- `_parseApeTag`: parses APE tags.
- `_parseMp4Tags`: parses MP4/M4A atoms.
- `_readMp4DataPayloads`: reads MP4 data atom payloads.
- `_parseMp4Cover`: extracts MP4 cover art.
- `_parseFlacBlocks`: parses FLAC Vorbis comments and pictures.
- `parseDurationFromFile`: estimates media duration.
- `_parseWithMediaMetadata`: uses platform metadata library.
- `_parseFromFilename`: fallback title/artist parsing.
- `parseTagsFromAsset`: parses bundled assets.
- `_withDurationFallback`: fills missing duration.
- `_parseContainerDuration`: reads duration from container structure.
- `_mpegBitrate`: resolves MPEG bitrate tables.
- `_coverFileExtension`: chooses cover file extension.
- `_decodeString`: decodes tag strings.

### `CoverExtractor`

Functions:

- `extractCover`: extracts cover from a local file.
- `getCoverFromAssets`: finds cover next to bundled assets.

### `CoverColorService`

Functions:

- Generates `CoverArtPalette`.
- Extracts dominant/accent/background colors from cover art.
- Provides fallback colors when art is missing.

### `YoutubeMusicService`

Flutter service that calls Python/Android helpers.

Data classes:

- `YoutubeMusicResult`: search result data.
- `YoutubeMusicDownload`: download result.
- `YoutubeVideoQuality`: available video quality.
- `YoutubeSubtitleOption`: subtitle choice.
- `YoutubeMusicStream`: stream URLs, qualities, subtitles.

Functions:

- `isSupported`: whether YouTube bridge is available.
- `usesNativeChannel`: true on Android.
- `add`: bridge smoke test.
- `search`: searches YouTube Music.
- `download`: downloads audio/video/subtitles.
- `resolvedDownloadDirectory`: returns actual output folder.
- `stream`: resolves stream from search result.
- `streamVideoId`: resolves stream by video id.
- `warmStreams`: preloads stream URLs for results.
- `_resolveStream`: core stream cache/load logic.
- `_resolveDownloadDirectory`: chooses settings/default path.
- `_ensureWritableDirectory`: creates/verifies output folder.
- `defaultYoutubeMusicDownloadDirectory`: platform default folder.
- `_cacheKey`: stream cache key.
- `_trimStreamCache`: limits stream cache size.
- `_runPython`: invokes Python/channel command and parses progress.
- `_desktopPythonExecutable`: finds Python executable.
- `_pythonScriptPath`: finds bundled Python script.
- `_friendlyPythonError`: converts technical Python errors into readable messages.

### `LocalShareService`

Local network transfer service.

Data classes:

- `ShareServerInfo`: local server URL/device info.
- `DiscoveredShareDevice`: discovered remote server.
- `RemoteShareManifest`: remote device and track list.
- `RemoteShareTrack`: one remote track.
- `ShareTransferProgress`: progress, speed, current file.

Functions:

- `startSharing`: starts HTTP server and UDP discovery responder.
- `stopSharing`: stops sharing.
- `discoverDevices`: scans network candidates and UDP responses.
- `fetchManifest`: downloads remote manifest.
- `downloadTracks`: downloads selected files with progress.
- `cancelTransfer`: cancels download.
- `pauseTransfer`: pauses download loop.
- `resumeTransfer`: resumes download.
- `_handleRequest`: serves manifest or file.
- `_startDiscoveryResponder`: responds to discovery packets.
- `_writeManifest`: sends JSON manifest.
- `_writeFile`: streams a music file.
- `_trackJson`: serializes a shared track.
- `_tracksForScope`: current song vs full library.
- `_canShareFile`: validates file path.
- `_localUrls`: returns share URLs for local interfaces.
- `_candidateProbeUrls`: builds likely local network targets.
- `_probeShareServer`: checks one URL.
- `_subnetBroadcastAddresses`: finds broadcast addresses.
- `_transferSpeed`: calculates speed.
- `_syncDirectory`: returns target sync directory.
- `_existingSyncedPath`: avoids duplicate downloads.
- `_findSyncedPathBySimilarName`: finds already synced similar file.
- `_isAudioFilePath`: checks supported audio extension.
- `_songNamesMatch`: compares normalized names.
- `_safeFileName`: removes unsafe filename chars.
- `_asciiDownloadFileName`: fallback filename.
- `_deviceName`: current device name.

### `WifiDirectService`

Android Wi-Fi Direct helper.

Data classes:

- `NearbyShareDevice`: a discovered nearby device.
- `WifiDirectConnectionInfo`: group owner/address data.

Functions:

- `isAndroid`: platform check.
- `isWifiDirectSupported`: asks native Android support.
- `ensurePermissions`: asks permissions.
- `searchDevices`: discovers Wi-Fi Direct/local devices.
- `connectWifiDirect`: connects to a device.
- `disconnectWifiDirect`: disconnects.
- `stopDiscovery`: stops scan.
- `trustDevice`: saves trusted device ID.
- `_trustedDeviceIds`: loads trusted IDs.

### `MusicBrainzTagService`

Metadata lookup service.

Functions:

- `findBestTagForMusic`: searches using a `Music` object.
- `findBestTag`: returns top scored tag.
- `searchTags`: returns possible matches.
- `_fetchRecordingSearch`: calls MusicBrainz API.
- `_recordingQueries`: builds Lucene query strings.
- `_scoreTag`: scores match quality.
- `_sameToken`: compares normalized tokens.
- `_normalizeToken`: normalizes names.
- `_cleanSearchText`: removes noise.
- `_lucenePhrase`: escapes phrase query.
- `_luceneTerm`: escapes term query.

### `PlayerAudioHandler`

Integrates with OS/background media controls.

Functions:

- `openTrack`: opens a track in audio handler.
- `updateNowPlayingOnly`: updates metadata without playback command.
- `updateNowPlaying`: updates metadata, controls, state, timeline.
- `setExternalPlaybackState`: syncs outside playback state.
- `playFromService`: backend play.
- `pauseFromService`: backend pause.
- `seekFromService`: backend seek.
- `setVolumeFromService`: backend volume.
- `play`: OS play command.
- `pause`: OS pause command.
- `click`: media button handler.
- `_togglePlayPauseNow`: toggle from OS.
- `seek`: OS seek.
- `skipToNext`: OS next.
- `skipToPrevious`: OS previous.
- `stop`: OS stop.
- `getChildren`: media browser children.
- `_controlsFor`: media controls list.
- `_broadcastState`: sends playback state.
- `_metadataTitle`: safe title.
- `_metadataArtist`: safe artist.
- `_updateWindowsMetadata`: updates SMTC metadata.
- `_updateWindowsTimeline`: updates SMTC timeline.
- `_guardWindowsSmtc`: protects against SMTC failures.
- `_safeSmtcText`: safe SMTC string.
- `_safeSmtcThumbnail`: safe thumbnail path.
- `disposeHandler`: cleanup.

### `PerformancePolicy`

Controls expensive UI effects.

Important getters:

- `allowDecorativeAnimations`.
- `allowParticles`.
- `allowBackdropBlur`.
- `maxGlassBlur`.
- `backgroundBlur`.
- `particleCountScale`.
- `coverCacheScale`.
- `listCacheExtent`.

### `Responsive`

Static responsive helper.

Functions/getters:

- `init`: reads `MediaQuery`.
- `scale`, `scaleW`, `scaleH`: responsive scale factors.
- `w`, `h`, `sp`, `s`: size helpers.
- `wp`, `hp`: viewport percentage helpers.
- `isTablet`, `isDesktop`, `isLandscape`, `isCompact`: breakpoint helpers.
- `ResponsiveExtension`: allows `10.w`, `10.h`, `14.sp`, etc.

## 9. Widgets

### `MusicCard`

Displays a track in card or list mode.

Functions:

- `_buildListView`: list row UI.
- `_buildCardView`: card UI.
- `_showGlassContextMenuFromLongPress`: opens menu on touch.
- `_showGlassContextMenu`: context menu.
- `_fitMenuAxis`: keeps menu on screen.
- `_buildMenuItem`: menu action row.
- `_showTrackInfoDialog`: full track information.
- `_buildInfoRow`: info row.
- `_buildInfoAction`: action button.
- `_openTrack`: opens file externally.
- `_formatTrackDuration`: duration display.
- `_showEditMetadataDialog`: edit metadata.
- `_autoTagWithMusicBrainz`: auto match and apply tags.
- `_showManualMusicBrainzTagDialog`: manual search dialog.
- `_showMusicBrainzResultsDialog`: result picker.
- `_applyMusicBrainzTag`: applies selected tag.
- `_pickCoverArt`: selects custom cover.
- `_buildGlassField`: text field style.
- `_showAddToPlaylistDialog`: playlist picker.

### `AudioEffectsMenu`

Bottom sheet for audio effects.

Parts:

- `_Header`: title/reset controls.
- `_PlaybackCard`: speed/pitch controls.
- `_ToneCard`: reverb/tone controls.
- `_EqualizerCard`: EQ enable/preset/reset.
- `_VerticalEqBands`: vertical EQ sliders.
- `_SongScopeTile`: per-song/global toggle.
- `_EffectCard`: reusable card.
- `_ReleaseSlider`, `_BareReleaseSlider`, `_BareSlider`: sliders.
- `_QuickAction`: small action button.
- `_ToneButton`: preset tone button.
- `showAudioEffectsMenu`: opens the menu.

### `PlaybackProgressControl`

Progress slider with stable behavior during track changes.

Functions:

- `didUpdateWidget`: resets visual state when track changes.
- `build`: renders position/duration/progress.
- `_progressFor`: converts position/duration to 0..1.

### `CoverArtTexture`

Displays cover art from local file, network URL, browser blob, or fallback icon.

Functions:

- `_isBrowserImage`: detects browser image URL.
- `_buildDefaultCover`: fallback artwork.
- `_NetworkCoverArt`: tries multiple URL candidates.
- `_coverCandidates`: generates alternate thumbnail URLs.

### `ParticleSystem`

Animated background particles.

Functions:

- `_initParticles`: creates particles.
- `_getParticleCount`: scales count by performance/device.
- `Particle.reset`: randomizes particle.
- `Particle.update`: moves particle.
- `ParticlePainter.paint`: draws particles.
- `_getParticleColor`: chooses color by effect.
- `_drawSakura`: petal shape.
- `_drawRain`: rain streak.

### Other Widgets

- `GlassContainer`: clipped blur/translucent panel.
- `PlaylistCard`: large playlist card with context menu.
- `SmallPlaylistCard`: compact playlist tile.
- `SettingsDrawer`: compact settings UI.
- `StableVideoSurface`: prevents video texture resize issues, especially Windows.
- `FadeInUpAnimation`: entrance animation.
- `ShowUpControl`: toggles child visibility.
- `PageSwitchButton`: basic navigation switch button.

## 10. Python Backend

### `lib/python/api.py`

Desktop Python backend.

General helpers:

- `safe_filename`: removes unsafe filename characters.
- `unique_path`: avoids overwriting files.
- `unique_media_stem`: creates unique media output name.
- `download_bytes`: downloads bytes from URL.
- `download_to_file`: downloads URL to path.
- `detect_mime`: detects file MIME type.
- `thumbnail_candidates`: collects possible thumbnail URLs.
- `high_quality_thumbnail_urls`: transforms thumbnail URL to better sizes.
- `detect_image_mime`: detects JPEG/PNG/WebP/GIF/BMP from bytes.
- `download_best_cover`: downloads best available thumbnail/cover.
- `preview_thumbnail_url`: returns preview cover URL.
- `best_thumbnail`: chooses best thumbnail from metadata.
- `format_track_no`: formats track number.
- `duration_seconds_from_value`: parses duration strings/numbers.
- `extract_duration_seconds`: extracts duration from metadata entities.

Classes:

- `SearchItem`: normalized search result.
- `MediaDownloader`: class that handles detailed audio/video download behavior.

YouTube functions:

- `search_youtube_music`: searches YouTube Music and returns JSON.
- `_download_youtube_video_file`: downloads a video file at selected quality.
- `_download_youtube_video_subtitles_only`: downloads subtitle sidecars.
- `_read_youtube_video_manifest`: reads manifest JSON.
- `_find_youtube_video_manifest`: finds existing manifest by video ID.
- `_subtitle_manifest_map`: maps subtitle manifest entries.
- `_find_manifest_quality`: finds quality entry.
- `_video_download_format_selector`: builds yt-dlp format selector.
- `_download_video_subtitle_sidecars`: downloads subtitles.
- `_choose_subtitle_track`: picks manual/automatic subtitle track.
- `_subtitle_language_from_filename`: guesses language.
- `download_youtube_music`: main download entry for audio/video/subtitles.
- `_library_files_for_download`: chooses files returned to Flutter library.
- `_download_message`: builds result message.
- `_video_quality_label`: display quality label.
- `_select_video_format`: chooses best format.
- `_collect_video_qualities`: lists available qualities.
- `_collect_subtitles`: lists subtitle options.
- `stream_youtube_music`: resolves stream URL/qualities/subtitles.
- `_emit_progress`: prints progress JSON to stdout.
- `_parse_int_list`: parses CSV ints.
- `_parse_text_list`: parses CSV strings.
- `_main`: CLI entrypoint.

### `android/app/src/main/python/mymodule.py`

Android Python backend.

Functions:

- `add`: bridge smoke test.
- `_client`: creates YouTube Music client.
- `_safe_filename`: safe Android filename.
- `_duration_seconds`: parses duration.
- `_extract_duration_seconds`: gets duration from search/download entities.
- `_unique_stem`: avoids duplicate output names.
- `_delete_stale_outputs`: removes old sidecar files for same media.
- `_artist_text`: joins artist names.
- `_thumbnail_candidates`: gathers thumbnails.
- `_high_quality_thumbnail_urls`: improves thumbnail URLs.
- `_detect_image_mime`: detects cover image type.
- `_best_thumbnail`: chooses thumbnail.
- `_cover_bytes`: downloads cover.
- `_preview_thumbnail_url`: preview art URL.
- `_delete_sidecar_images`: removes old cover images.
- `_write_media_tags`: writes title/artist/album/cover tags.
- `_search_item`: normalizes result.
- `search_youtube_music`: searches YouTube Music.
- `_entity_from_item`: refetches selected entity.
- `_track_fields`: extracts title/artist.
- `_download_track`: downloads one track.
- `download_youtube_music`: main Android download.
- `stream_youtube_music`: resolves stream URL.

## 11. Important Data Flow

### Local Music Scan Flow

1. User adds source path in settings.
2. `SettingsModel.addMusicPath` saves the path.
3. `MusicService.loadSystemMusic` starts scan.
4. `MusicScannerService` finds files.
5. `ID3Parser` reads metadata/duration/cover.
6. `CoverExtractor` extracts artwork.
7. `MusicService` merges old favorites/stats.
8. Library snapshot is saved.
9. UI pages update through Provider notifications.

### Playback Flow

1. User taps a `MusicCard`.
2. `MusicService.playMusicFromQueue`, `playPlaylist`, or `play` selects track.
3. `_preparePlayerForTrack` configures backend.
4. `_openTrackMedia` opens file/URL.
5. `_applyAudioEffects` and decoder settings are applied.
6. `_smoothOpenAndPlay` starts playback.
7. `PlayerAudioHandler` updates OS media controls.
8. Position/duration streams update UI.

### YouTube Stream Flow

1. User searches in `YoutubeMusicPage`.
2. `YoutubeMusicService.search` calls Python/channel.
3. Results become `YoutubeMusicResult`.
4. User taps stream.
5. `YoutubeMusicService.stream` resolves URL/qualities/subtitles.
6. `MusicService.playStreamingMusic` creates streaming `Music`.
7. Normal playback UI handles the stream.

### YouTube Download Flow

1. User chooses download options.
2. `YoutubeMusicService.download` sends options to Python.
3. Python downloads audio/video/subtitles and metadata.
4. Python returns downloaded file paths and message.
5. `MusicService.loadSystemMusic` or import refresh includes new files.

### Lyrics Flow

1. Player page opens lyrics sheet.
2. `MusicService.loadLyricsDocumentForCurrent` searches manual files/sidecars.
3. If needed, user searches online.
4. LRCLIB results are scored.
5. Selected lyrics are saved next to app lyrics data.
6. `LyricsDocument.activeIndexAt` highlights current line.

### Sharing Flow

1. Host starts sharing current song or library.
2. `LocalShareService.startSharing` creates HTTP server and discovery responder.
3. Receiver scans with `discoverDevices`.
4. Receiver fetches manifest.
5. Receiver downloads selected tracks.
6. `MusicService.importSharedMusicFiles` imports new files.

## 12. Build And Platform Support

Configured platforms:

- Android.
- Web.
- Windows.

README mentions intended support for:

- Android API 21+.
- iOS 13+.
- Windows 10+.
- macOS 10.15+.
- Linux Ubuntu 18.04+.

Actual repository folders currently visible:

- `android`.
- `web`.
- `windows`.

## 13. Notes For Future Development

- `MusicService` is very large and owns many responsibilities. Future refactors could split it into playback, library, lyrics, queue, and effects services.
- Python backend has separate desktop and Android implementations; keep behavior aligned when changing YouTube features.
- Video quality/subtitle handling depends on manifests; avoid changing manifest format without migration.
- Settings are stored in `SharedPreferences`; renaming keys will lose old user preferences unless migrated.
- Library identity depends on IDs and file paths; changing ID logic affects favorites/playlists/stats.
- Audio effect support differs by backend/platform; always test Windows native and normal media_kit paths.

