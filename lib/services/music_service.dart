import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb, compute, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/lyrics_model.dart';
import '../models/lyrics_provider_model.dart';
import '../models/music_model.dart';
import '../models/playback_snapshot.dart';
import '../models/playlist_model.dart';
import 'app_directories.dart';
import 'lyrics_manager.dart';
import 'lrclib_service.dart';
import 'music_scanner_service.dart';
import 'player_audio_handler.dart';
import 'video_playback_service.dart';
import 'cpp_core_bridge.dart';
import 'lyrics_aligner_service.dart';
import 'youtube_music_service.dart';

List<Music> _parseLibrarySnapshotFromJson(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return [];
  return decoded
      .whereType<Map>()
      .map((item) => Music.fromJson(Map<String, dynamic>.from(item)))
      .where((m) => m.id.isNotEmpty && m.filePath.isNotEmpty)
      .toList();
}

class MusicService extends ChangeNotifier with WidgetsBindingObserver {
  static const String _playbackStateKey = 'playback_state';
  static const String _rememberPlaybackKey = 'remember_playback_enabled';
  static const String _librarySnapshotKey = 'music_library_snapshot';

  List<Music> _musicList = [];
  List<Music> _activeQueue = []; // ordered list currently being played (may be subset/sorted)
  Music? _streamingMusic;
  List<Music> _streamingQueue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final PlayerAudioHandler _audioHandler;
  double _volume = 100.0;

  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _playingNotifier = ValueNotifier(false);
  final ValueNotifier<double> _volumeNotifier = ValueNotifier(100.0);
  final ValueNotifier<Music?> _currentMusicNotifier = ValueNotifier(null);
  final ValueNotifier<int> _currentIndexNotifier = ValueNotifier(0);

  // Lyrics state
  LyricsDocument? _currentLyrics;
  bool _lyricsLoading = false;
  String? _lyricsError;
  final _lyricsController = StreamController<Duration>.broadcast();

  // Singleton reference so the position callback can reach the active instance
  static MusicService? _instance;

  bool _isInitialized = false;
  bool _isLoadingSystemMusic = false;
  Timer? _positionTimer;
  DateTime _lastPositionUpdate = DateTime.now();
  String? _openedFilePath; // tracks which file is open in C++ engine
  String? _lastOpenedOriginalPath; // original path of the currently-open file
  bool _completionFired = false; // prevents double-firing on track end

  /// True when the native C++ engine is available (Windows desktop).
  bool get _usingCppEngine => !kIsWeb && Platform.isWindows;

  // Fallback audio player for formats not supported by C++ engine (e.g., M4A on Windows)
  AudioPlayer? _fallbackPlayer;
  bool _usingFallbackPlayer = false;

  List<Playlist> _playlists = [];
  String? _currentPlaylistId;
  bool _isShuffle = false;
  bool _isRepeatOne = false;
  bool _isRepeatAll = true;

  List<Music> _cachedEarlyListened = [];
  int _dataVersion = 0;
  List<Music>? _cachedRecommended;
  int _recommendedVersion = -1;
  LibraryStatsDashboard? _cachedStats;
  int _statsVersion = -1;

  MusicService() {
    _instance = this;
    WidgetsBinding.instance.addObserver(this);
    _audioHandler = playerAudioHandler;
    _audioHandler
      ..onTogglePlayPauseCommand = _handleSystemTogglePlayPause
      ..onPlayCommand = _handleSystemPlay
      ..onPauseCommand = _handleSystemPause
      ..onNextCommand = _handleSystemNext
      ..onPreviousCommand = _handleSystemPrevious
      ..onSeekCommand = _handleSystemSeek
      ..onCompleted = _handleSystemCompleted;
    try {
      CppCoreBridge.initialize();
      debugPrint('[pvf] CppCoreBridge.initialize() OK, engineInit=${CppCoreBridge.isInitialized()}, engineReady=${CppCoreBridge.isReady()}');
      // Enable vocal detection for charter sync
      CppCoreBridge.setVocalDetectionEnabled(true);
    } catch (e) {
      debugPrint('[pvf] CppCoreBridge.initialize() CRASHED: $e');
    }
    // Initialize fallback player for platforms without the C++ engine
    // (web, Android, iOS, ...) and for unsupported formats on Windows (M4A).
    if (!_usingCppEngine) {
      _fallbackPlayer = AudioPlayer();
      _fallbackPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _handleFallbackCompleted();
        }
      });
      _fallbackPlayer!.positionStream.listen((pos) {
        if (_usingFallbackPlayer) {
          _position = pos;
          _positionNotifier.value = pos;
        }
      });
      _fallbackPlayer!.durationStream.listen((dur) {
        if (_usingFallbackPlayer && dur != null) {
          _duration = dur;
          _durationNotifier.value = dur;
        }
      });
    }
    _wirePositionCallback();
    _startPositionPolling();
    _initializeAsync();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _currentMusicNotifier.dispose();
    _currentIndexNotifier.dispose();
    CppCoreBridge.shutdown();
    _lyricsController.close();
    _fallbackPlayer?.dispose();
    super.dispose();
  }

  static const String _lastTrackIdKey = 'last_played_track_id';
  static const String _lastPositionKey = 'last_played_position_ms';
  static const String _lastIndexKey = 'last_played_queue_index';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _savePlaybackState();
    }
  }

  Future<void> _savePlaybackState() async {
    if (!_rememberPlayback) return;
    final music = currentMusic;
    if (music == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastTrackIdKey, music.id);
      await prefs.setInt(_lastPositionKey, _position.inMilliseconds);
      await prefs.setInt(_lastIndexKey, _currentIndex);
    } catch (e) {
      debugPrint('PlaybackState: save failed: $e');
    }
  }

  Future<void> _restorePlayback() async {
    if (!_rememberPlayback) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final trackId = prefs.getString(_lastTrackIdKey);
      final positionMs = prefs.getInt(_lastPositionKey) ?? 0;
      final queueIndex = prefs.getInt(_lastIndexKey) ?? 0;

      if (trackId == null) return;

      final queue = _activeQueue.isNotEmpty ? _activeQueue : _musicList;
      final idx = queue.indexWhere((m) => m.id == trackId);
      if (idx < 0) return;

      _currentIndex = idx;
      _currentIndexNotifier.value = idx;
      if (_activeQueue.isNotEmpty) {
        _currentMusicNotifier.value = _activeQueue[idx];
      }
      _position = Duration(milliseconds: positionMs);
      _positionNotifier.value = _position;
      notifyListeners();

      debugPrint('[pvf] Restored playback: track=$trackId index=$idx pos=${_position.inSeconds}s');
    } catch (e) {
      debugPrint('PlaybackState: restore failed: $e');
    }
  }

  Future<void> _initializeAsync() async {
    await _loadSettingsAsync();
    await _loadLibrarySnapshotAsync();
    await _restorePlayback();
    _isInitialized = true;
    _currentMusicNotifier.value = currentMusic;
    _currentIndexNotifier.value = _currentIndex;
    notifyListeners();
    unawaited(_refreshLibraryAfterFirstFrame());
  }

  Future<void> _refreshLibraryAfterFirstFrame() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (_isLoadingSystemMusic) return;
    await loadSystemMusic(clearExisting: true);
  }

  void _startPositionPolling() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_usingFallbackPlayer && _usingCppEngine) {
        CppCoreBridge.update();
      }
    });
  }

  /// Wire the C++ position callback so position/duration/playing come from the engine.
  void _wirePositionCallback() {
    if (!_usingCppEngine) return;
    try {
      CppCoreBridge.attachPositionCallback(_onCppPosition);
      debugPrint('[pvf] Position callback wired OK');
    } catch (e) {
      debugPrint('[pvf] Position callback wiring FAILED: $e');
    }
  }

  /// Static entry point called by the C++ engine ~4×/sec with current state.
  @pragma('vm:entry-point')
  static void _onCppPosition(int posMs, int durMs, bool playing) {
    final svc = _instance;
    if (svc == null) return;
    if (svc._usingFallbackPlayer) return; // Skip C++ updates when using fallback player

    final pos = Duration(milliseconds: posMs);
    final dur = Duration(milliseconds: durMs < 0 ? 0 : durMs);

    // Update notifiers (high-frequency — no notifyListeners() here).
    if (svc._positionNotifier.value != pos) {
      svc._position = pos;
      svc._positionNotifier.value = pos;
      svc._emitPosition(pos);
    }
    if (dur > Duration.zero && svc._durationNotifier.value != dur) {
      svc._duration = dur;
      svc._durationNotifier.value = dur;
    }

    // Detect track completion: position reached end and engine stopped playing.
    final isNearEnd = dur > Duration.zero &&
        pos >= dur - const Duration(milliseconds: 500);
    if (isNearEnd && !playing && svc._isPlaying && !svc._completionFired) {
      svc._completionFired = true;
      svc._isPlaying = false;
      svc._playingNotifier.value = false;
      unawaited(svc._handleSystemCompleted());
    } else if (!isNearEnd) {
      svc._completionFired = false;
    }
  }

  // Playback controls via C++ bridge
  Future<void> play() async {
    final current = currentMusic;
    if (current == null) {
      debugPrint('[pvf] play() ABORT: currentMusic is null');
      return;
    }
    
    // Ensure C++ bridge is initialized
    if (!CppCoreBridge.isBridgeInitialized()) {
      debugPrint('[pvf] CppCoreBridge not initialized, initializing now...');
      CppCoreBridge.initialize();
    }
    
    debugPrint('[pvf] play() called for: ${current.title}');
    debugPrint('[pvf]   filePath=${current.filePath}');
    debugPrint('[pvf]   _openedFilePath=$_openedFilePath');
    debugPrint('[pvf]   engineReady=${CppCoreBridge.isReady()}, engineInit=${CppCoreBridge.isInitialized()}');

    // Only re-open the file when the track actually changed.
    if (_lastOpenedOriginalPath != current.filePath) {
      debugPrint('[pvf]   Opening file: ${current.filePath}');
      final openedPath = await _openFileWithFallback(current.filePath);
      debugPrint('[pvf]   openFile returned: $openedPath');
      if (openedPath == null) {
        debugPrint('[pvf]   ABORT: could not open file');
        return;
      }
      _openedFilePath = openedPath;
      _lastOpenedOriginalPath = current.filePath;
      _completionFired = false;
      _positionNotifier.value = Duration.zero;
      _position = Duration.zero;
      unawaited(_audioHandler.openTrack(current));
      unawaited(autoLoadLyrics());
    }

    if (_usingFallbackPlayer && _fallbackPlayer != null) {
      debugPrint('[pvf]   Calling _fallbackPlayer.play()...');
      await _fallbackPlayer!.play();
      _isPlaying = true;
      _playingNotifier.value = true;
      unawaited(_audioHandler.updateNowPlaying(
        current,
        playing: true,
        position: _position,
        duration: current.duration,
      ));
      notifyListeners();
      debugPrint('[pvf]   play() SUCCESS (fallback) — _isPlaying=true');
      return;
    }

    debugPrint('[pvf]   Calling CppCoreBridge.play()...');
    final playOk = CppCoreBridge.play();
    debugPrint('[pvf]   CppCoreBridge.play() returned: $playOk');
    if (!playOk) {
      debugPrint('[pvf]   ABORT: play() failed');
      return;
    }
    _isPlaying = true;
    _playingNotifier.value = true;
    unawaited(_audioHandler.updateNowPlaying(
      current,
      playing: true,
      position: _position,
      duration: current.duration,
    ));
    notifyListeners();
    debugPrint('[pvf]   play() SUCCESS — _isPlaying=true');
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      if (_usingFallbackPlayer && _fallbackPlayer != null) {
        await _fallbackPlayer!.pause();
      } else {
        CppCoreBridge.pause();
      }
      _isPlaying = false;
    } else {
      final current = currentMusic;
      if (current == null) return;

      // Open file if not already open.
      if (_lastOpenedOriginalPath != current.filePath) {
        final openedPath = await _openFileWithFallback(current.filePath);
        if (openedPath == null) {
          debugPrint('[pvf] togglePlayPause: openFile failed for: ${current.filePath}');
          return;
        }
        _openedFilePath = openedPath;
        _lastOpenedOriginalPath = current.filePath;
        _completionFired = false;
        unawaited(_audioHandler.openTrack(current));
      }

      if (_usingFallbackPlayer && _fallbackPlayer != null) {
        await _fallbackPlayer!.play();
        _isPlaying = true;
      } else {
        final playOk = CppCoreBridge.play();
        if (!playOk) {
          debugPrint('[pvf] togglePlayPause: play() failed');
          return;
        }
        _isPlaying = true;
      }
    }
    _playingNotifier.value = _isPlaying;
    final current = currentMusic;
    if (current != null) {
      unawaited(_audioHandler.updateNowPlaying(
        current,
        playing: _isPlaying,
        position: _position,
        duration: current.duration,
      ));
    }
    notifyListeners();
  }

  Future<String?> _openFileWithFallback(String filePath) async {
    // Platforms without the native C++ engine (web, Android, iOS, ...) play
    // entirely through just_audio.
    if (!_usingCppEngine) {
      return _openWithJustAudio(filePath);
    }

    final exists = await File(filePath).exists();
    if (!exists) {
      debugPrint('[pvf] openFile: file does not exist: $filePath');
      return null;
    }

    final ok = CppCoreBridge.openFile(filePath);
    if (ok) {
      _usingFallbackPlayer = false;
      return filePath;
    }

    debugPrint('[pvf] openFile: C++ failed for: $filePath');

    // Fallback 1: copy to a temp ASCII path and retry
    try {
      final tempDir = Directory.systemTemp;
      final ext = p.extension(filePath);
      final base = p.basenameWithoutExtension(filePath);
      final asciiBase = base.replaceAll(RegExp(r'[^\x00-\x7F]'), '_');
      final tempPath = p.join(tempDir.path, '$asciiBase$ext');

      await File(filePath).copy(tempPath);
      debugPrint('[pvf] openFile: copied to temp path: $tempPath');

      final retryOk = CppCoreBridge.openFile(tempPath);
      if (retryOk) {
        _usingFallbackPlayer = false;
        return tempPath;
      }
    } catch (e) {
      debugPrint('[pvf] openFile: fallback failed: $e');
    }

    // Fallback 2: use just_audio for unsupported formats (e.g., M4A on Windows).
    return _openWithJustAudio(filePath);
  }

  Future<String?> _openWithJustAudio(String filePath) async {
    final player = _fallbackPlayer;
    if (player == null) return null;
    final uri = _resolvePlayableUri(filePath);
    if (uri == null) {
      debugPrint('[pvf] openFile: no playable URI for: $filePath');
      return null;
    }
    try {
      debugPrint('[pvf] openFile: trying just_audio fallback for: $uri');
      await player.setAudioSource(AudioSource.uri(uri));
      _usingFallbackPlayer = true;
      debugPrint('[pvf] openFile: just_audio fallback succeeded');
      return filePath; // Return original path to track which file is playing
    } catch (e) {
      debugPrint('[pvf] openFile: just_audio fallback failed: $e');
    }
    return null;
  }

  Uri? _resolvePlayableUri(String path) {
    if (kIsWeb) {
      final parsed = Uri.tryParse(path);
      if (parsed != null &&
          (parsed.scheme == 'http' || parsed.scheme == 'https')) {
        return parsed;
      }
      return null; // local file paths are not reachable from a browser
    }
    return Uri.file(path);
  }

  Future<void> pause() async {
    if (_usingFallbackPlayer && _fallbackPlayer != null) {
      await _fallbackPlayer!.pause();
    } else {
      CppCoreBridge.pause();
    }
    _isPlaying = false;
    _playingNotifier.value = false;
    notifyListeners();
  }

  Future<void> stop() async {
    if (_usingFallbackPlayer && _fallbackPlayer != null) {
      await _fallbackPlayer!.stop();
    } else {
      CppCoreBridge.stop();
    }
    _isPlaying = false;
    _position = Duration.zero;
    _openedFilePath = null;
    _lastOpenedOriginalPath = null;
    _usingFallbackPlayer = false;
    _playingNotifier.value = false;
    _positionNotifier.value = Duration.zero;
    notifyListeners();
  }

  Future<void> next() async {
    final queue = _activeQueue.isNotEmpty ? _activeQueue : _musicList;
    if (queue.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % queue.length;
    _currentIndex = nextIndex;
    _currentIndexNotifier.value = nextIndex;
    if (_activeQueue.isNotEmpty) {
      _currentMusicNotifier.value = _activeQueue[nextIndex];
    }
    notifyListeners();
    unawaited(autoLoadLyrics());
    await play();
  }

  Future<void> previous() async {
    final queue = _activeQueue.isNotEmpty ? _activeQueue : _musicList;
    if (queue.isEmpty) return;
    final prevIndex = (_currentIndex - 1 + queue.length) % queue.length;
    _currentIndex = prevIndex;
    _currentIndexNotifier.value = prevIndex;
    if (_activeQueue.isNotEmpty) {
      _currentMusicNotifier.value = _activeQueue[prevIndex];
    }
    notifyListeners();
    unawaited(autoLoadLyrics());
    await play();
  }

  Future<void> seekTo(Duration position) async {
    if (_usingFallbackPlayer && _fallbackPlayer != null) {
      await _fallbackPlayer!.seek(position);
    } else {
      CppCoreBridge.seek(position.inMilliseconds);
    }
    _position = position;
    _positionNotifier.value = position;
    notifyListeners();
  }

  void setVolume(double volume) {
    _volume = volume.clamp(0.0, 100.0).toDouble();
    _volumeNotifier.value = _volume;
    if (_usingFallbackPlayer && _fallbackPlayer != null) {
      _fallbackPlayer!.setVolume(_volume / 100.0);
    } else {
      CppCoreBridge.setVolume(_volume);
    }
  }

  void adjustVolumeBy(double delta) {
    setVolume(_volume + delta);
  }

  void toggleMute() {
    if (_volume > 0) {
      _lastAudibleVolume = _volume;
      setVolume(0);
    } else {
      setVolume(_lastAudibleVolume);
    }
  }

  double _lastAudibleVolume = 70.0;

  // System command handlers
  Future<void> _handleSystemPlay() async {
    if (currentMusic == null && _musicList.isNotEmpty) {
      await play();
      return;
    }
    if (!_isPlaying) await togglePlayPause();
  }

  Future<void> _handleSystemTogglePlayPause() async {
    if (currentMusic == null && _musicList.isNotEmpty) {
      await play();
      return;
    }
    await togglePlayPause();
  }

  Future<void> _handleSystemPause() async {
    if (_isPlaying) await togglePlayPause();
  }

  Future<void> _handleSystemNext() async => next();
  Future<void> _handleSystemPrevious() async => previous();
  Future<void> _handleSystemSeek(Duration position) async => seekTo(position);
  Future<void> _handleSystemCompleted() async {
    if (_isRepeatOne) {
      await seekTo(Duration.zero);
      await play();
    } else {
      await next();
    }
  }

  void _handleFallbackCompleted() {
    if (!_usingFallbackPlayer) return;
    _handleSystemCompleted();
  }

  // Getters
  List<Music> get musicList => _musicList;
  Music? get currentMusic => _streamingMusic ?? _libraryCurrentMusic;
  Music? get _libraryCurrentMusic {
    // Prefer active queue when it's set (sorted/filtered play context).
    final queue = _activeQueue.isNotEmpty ? _activeQueue : _musicList;
    return queue.isNotEmpty && _currentIndex < queue.length
        ? queue[_currentIndex]
        : null;
  }
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioPlayer? get audioPlayer => _audioHandler.audioPlayer;
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;
  ValueNotifier<Duration> get durationNotifier => _durationNotifier;
  ValueNotifier<bool> get playingNotifierValue => _playingNotifier;
  ValueNotifier<double> get volumeNotifier => _volumeNotifier;
  double get volume => _volume;
  bool get isLoadingSystemMusic => _isLoadingSystemMusic;
  int get systemMusicCount => _musicList.length;

  // --- Lyrics state ---
  LyricsDocument? get currentLyrics => _currentLyrics;
  bool get isLyricsLoading => _lyricsLoading;
  String? get lyricsError => _lyricsError;

  /// A broadcast stream of position updates. Works on all platforms
  /// (unlike AudioPlayer.positionStream which is null on Windows).
  Stream<Duration> get positionStream {
    // Emit current value on first listen so consumers don't miss the initial position.
    return _lyricsController.stream;
  }

  void _emitPosition(Duration pos) {
    if (!_lyricsController.isClosed) {
      _lyricsController.add(pos);
    }
  }

  /// Sets the cached lyrics (no-op if the track matches what's already cached).
  void setLyrics(LyricsDocument? doc, {String? error}) {
    _currentLyrics = doc;
    _lyricsError = error;
    _lyricsLoading = false;
    _syncAligner();
    notifyListeners();
  }

  /// Keeps the native WebRTC VAD + PocketSphinx aligner in sync with the
  /// currently loaded lyrics so word-by-word karaoke timing tracks real vocals.
  void _syncAligner() {
    if (!CppCoreBridge.isBridgeInitialized()) return;
    LyricsAlignerService.instance.configure(_currentLyrics);
  }

  void setLyricsLoading(bool loading) {
    _lyricsLoading = loading;
    notifyListeners();
  }

  // --- Auto-load lyrics when the track changes ---
  String? _lastLyricsTrackId;

  Future<void> autoLoadLyrics() async {
    final music = currentMusic;
    if (music == null) {
      _currentLyrics = null;
      _lyricsError = null;
      _lyricsLoading = false;
      _syncAligner();
      notifyListeners();
      return;
    }

    // Skip if already loaded for this track
    if (_lastLyricsTrackId == music.id && _currentLyrics != null) return;

    _lastLyricsTrackId = music.id;
    _currentLyrics = null;
    _lyricsError = null;
    _lyricsLoading = true;
    _syncAligner();
    notifyListeners();

    try {
      // Only search local files during auto-load to avoid launching Chrome
      // for the Turnstile challenge during playback. Online search is
      // triggered explicitly when the user opens the lyrics page.
      final doc = await loadLyricsDocumentForCurrent(searchOnline: false);
      if (_lastLyricsTrackId != music.id) return; // track changed during await
      if (doc != null && doc.lines.isNotEmpty) {
        _currentLyrics = doc;
        _lyricsError = null;
        _syncAligner();
      } else {
        _lyricsError = 'No local lyrics found';
      }
    } catch (e) {
      _lyricsError = 'Error loading lyrics: $e';
    } finally {
      _lyricsLoading = false;
      notifyListeners();
    }
  }

  /// Force an online lyrics search for the current track.
  /// This triggers the browser auth flow (Chrome + Turnstile challenge).
  Future<void> searchLyricsOnline() async {
    final music = currentMusic;
    if (music == null) return;

    _lastLyricsTrackId = music.id;
    _currentLyrics = null;
    _lyricsError = null;
    _lyricsLoading = true;
    _syncAligner();
    notifyListeners();

    try {
      final doc = await loadLyricsDocumentForCurrent(searchOnline: true);
      if (_lastLyricsTrackId != music.id) return;
      if (doc != null && doc.lines.isNotEmpty) {
        _currentLyrics = doc;
        _lyricsError = null;
        _syncAligner();
      } else {
        _lyricsError = 'No lyrics found';
      }
    } catch (e) {
      _lyricsError = 'Error loading lyrics: $e';
    } finally {
      _lyricsLoading = false;
      notifyListeners();
    }
  }
  List<Playlist> get playlists => _playlists;
  bool get isShuffle => _isShuffle;
  bool get isRepeatOne => _isRepeatOne;
  bool get isRepeatAll => _isRepeatAll;
  bool get isInitialized => _isInitialized;
  String? get currentPlaylistId => _currentPlaylistId;
  bool get isCurrentMediaVideo {
    final music = currentMusic;
    return music != null && isVideoMedia(music);
  }
  bool get videoControllerReady => false;
  bool isVideoMedia(Music music) => VideoPlaybackService.isVideoMedia(music);

  set currentIndex(int index) {
    if (index >= 0 && index < _musicList.length) {
      _currentIndex = index;
      _currentIndexNotifier.value = index;
      notifyListeners();
      unawaited(autoLoadLyrics());
    }
  }

  set currentPlaylistId(String? id) {
    _currentPlaylistId = id;
    notifyListeners();
  }

  void setShuffle(bool value) {
    _isShuffle = value;
    notifyListeners();
  }

  void setRepeatMode(bool repeatOne, bool repeatAll) {
    _isRepeatOne = repeatOne;
    _isRepeatAll = repeatAll;
    notifyListeners();
  }

  // Library scanning
  Future<void> loadSystemMusic({bool clearExisting = true, List<String>? customPaths}) async {
    if (_isLoadingSystemMusic) return;
    _isLoadingSystemMusic = true;
    notifyListeners();

    try {
      final paths = await MusicScannerService.scanSystemMusicFolders();
      final musicList =
          await MusicScannerService.createMusicListFromPaths(paths);
      if (clearExisting) {
        _musicList = musicList;
        // Only reset the active queue if nothing is currently playing —
        // otherwise the now-playing index would become invalid.
        if (!_isPlaying && _streamingMusic == null) {
          _activeQueue = [];
        }
      } else {
        _musicList.addAll(musicList);
      }
      _invalidateDataCache();
      notifyListeners();
      await _saveLibrarySnapshot();
    } catch (e) {
      debugPrint('Error loading system music: $e');
    } finally {
      _isLoadingSystemMusic = false;
      notifyListeners();
    }
  }

  void _invalidateDataCache() {
    _dataVersion++;
    _cachedRecommended = null;
    _cachedStats = null;
  }

  List<Music> get recommendedMusicList {
    if (_musicList.isEmpty) return const [];
    if (_cachedRecommended != null && _recommendedVersion == _dataVersion) {
      return _cachedRecommended!;
    }

    final now = DateTime.now();
    final scored = _musicList.map((music) {
      var score = 0.0;
      if (music.isFavorite) score += 80;
      score += music.playCount.clamp(0, 25) * 3;
      final ageDays = now.difference(music.dateAdded).inDays.clamp(0, 365);
      score += (365 - ageDays) / 365 * 10;
      final lastPlayedDays = music.lastPlayed == null
          ? 365
          : now.difference(music.lastPlayed!).inDays.clamp(0, 365);
      score += (365 - lastPlayedDays) / 365 * 8;
      return (music: music, score: score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final result =
        scored.map((item) => item.music).take(24).toList(growable: false);
    _cachedRecommended = result;
    _recommendedVersion = _dataVersion;
    return result;
  }

  List<Music> get earlyListenedMusicList =>
      List.unmodifiable(_cachedEarlyListened);
  List<Music> get recentlyAddedMusicList {
    final items = List<Music>.from(_musicList)
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return items.take(24).toList(growable: false);
  }

  LibraryStatsDashboard get libraryStatsDashboard {
    if (_cachedStats != null && _statsVersion == _dataVersion) {
      return _cachedStats!;
    }
    final total = _musicList.length;
    final liked = _musicList.where((m) => m.isFavorite).length;
    final result = LibraryStatsDashboard(
      totalRecords: total,
      musicRecords: total,
      videoRecords: 0,
      likedRecords: liked,
      playedRecords: _musicList.where((m) => m.lastPlayed != null).length,
      playlistCount: _playlists.length,
      totalPlays: _musicList.fold<int>(0, (sum, m) => sum + m.playCount),
      totalDuration: _musicList.fold<Duration>(
          Duration.zero, (sum, m) => sum + (m.duration ?? Duration.zero)),
      genreCount: _normalizedUniqueCount(_musicList.map((m) => m.genre)),
      artistCount: _normalizedUniqueCount(_musicList.map((m) => m.artist)),
      albumCount: _normalizedUniqueCount(_musicList.map((m) => m.album)),
      yearCount: _normalizedUniqueCount(_musicList.map((m) => m.year)),
      aiCandidates: recommendedMusicList.length,
      topGenre: _topRankItem(_musicList.map((m) => m.genre), 'No genre'),
      topArtist: _topRankItem(_musicList.map((m) => m.artist), 'No artist'),
      mediaSlices: const [],
      likedSlices: const [],
      playedSlices: const [],
      genreRanks: const [],
      artistRanks: const [],
      albumRanks: const [],
      yearRanks: const [],
      playlistRanks: const [],
      topPlayedTracks: const [],
      recentlyPlayed: const [],
      earlyListened: const [],
      recommendationSignals: const [],
    );
    _cachedStats = result;
    _statsVersion = _dataVersion;
    return result;
  }

  List<LibraryMiniStat> get libraryMiniStats {
    final dashboard = libraryStatsDashboard;
    return [
      LibraryMiniStat('Total', '${dashboard.totalRecords}', 1),
      LibraryMiniStat('Liked', '${dashboard.likedRecords}',
          _ratio(dashboard.likedRecords, dashboard.totalRecords)),
      LibraryMiniStat('Played', '${dashboard.playedRecords}',
          _ratio(dashboard.playedRecords, dashboard.totalRecords)),
      LibraryMiniStat('Playlists', '${dashboard.playlistCount}', 1),
    ];
  }

  List<Music> get favoriteMusicList =>
      _musicList.where((m) => m.isFavorite).toList();
  List<Playlist> get allPlaylists => List.unmodifiable(_playlists);

  // Playlist management
  void createPlaylist(String name) {
    final now = DateTime.now();
    final playlist = Playlist(id: _generateId(), name: name, musicIds: const [], createdAt: now, updatedAt: now);
    _playlists.add(playlist);
    notifyListeners();
  }

  void deletePlaylist(String playlistId) {
    _playlists.removeWhere((p) => p.id == playlistId);
    if (_currentPlaylistId == playlistId) _currentPlaylistId = null;
    notifyListeners();
  }

  void addMusicToPlaylist(String playlistId, String musicId) {
    final playlist = _playlists.firstWhereOrNull((p) => p.id == playlistId);
    if (playlist != null && !playlist.musicIds.contains(musicId)) {
      playlist.musicIds.add(musicId);
      notifyListeners();
    }
  }

  List<Music> getMusicListForPlaylist(String playlistId) {
    final playlist = _playlists.firstWhereOrNull((p) => p.id == playlistId);
    if (playlist == null) return [];
    return _musicList.where((m) => playlist.musicIds.contains(m.id)).toList();
  }

  // Metadata
  Future<void> updateMusicMetadata(
      String id, String title, String artist, String album, String genre,
      {String year = '', String? spotifyUrl}) async {
    final index = _musicList.indexWhere((m) => m.id == id);
    if (index == -1) return;
    _musicList[index] = _musicList[index].copyWith(
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      year: year,
      spotifyUrl: spotifyUrl ?? _musicList[index].spotifyUrl,
    );
    notifyListeners();
    await _saveLibrarySnapshot();
  }

  Future<void> toggleFavorite(String id) async {
    final index = _musicList.indexWhere((m) => m.id == id);
    if (index == -1) return;
    _musicList[index] =
        _musicList[index].copyWith(isFavorite: !_musicList[index].isFavorite);
    notifyListeners();
    await _saveLibrarySnapshot();
  }

  Future<void> setFavoriteForMusicIds(
    Iterable<String> ids,
    bool isFavorite,
  ) async {
    final targets = ids.toSet();
    if (targets.isEmpty) return;
    var changed = false;
    for (var i = 0; i < _musicList.length; i++) {
      final music = _musicList[i];
      if (targets.contains(music.id) && music.isFavorite != isFavorite) {
        _musicList[i] = music.copyWith(isFavorite: isFavorite);
        changed = true;
      }
    }
    if (!changed) return;
    _invalidateDataCache();
    notifyListeners();
    await _saveLibrarySnapshot();
  }

  Future<bool> deleteMusic(int index, {bool deleteFile = false}) async {
    if (index < 0 || index >= _musicList.length) return false;
    final music = _musicList[index];
    if (deleteFile && music.filePath.isNotEmpty) {
      try {
        final file = File(music.filePath);
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('Error deleting file: $e');
      }
    }
    _musicList.removeAt(index);
    if (_currentIndex >= _musicList.length) {
      _currentIndex = _musicList.length - 1;
    }
    notifyListeners();
    await _saveLibrarySnapshot();
    return true;
  }

  // Persistence
  Future<void> _loadSettingsAsync() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberPlayback = prefs.getBool(_rememberPlaybackKey) ?? true;
  }

  Future<void> _loadLibrarySnapshotAsync() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_librarySnapshotKey);
    if (raw != null) {
      _musicList = _parseLibrarySnapshotFromJson(raw);
      if (_musicList.isNotEmpty) {
        _currentIndex = 0;
      }
    }
  }

  Future<void> _saveLibrarySnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_musicList.map((m) => m.toJson()).toList());
    await prefs.setString(_librarySnapshotKey, json);
  }

  bool _rememberPlayback = true;

  // Helpers
  int _normalizedUniqueCount(Iterable<String> values) {
    final set = values
        .map((v) => v.trim().toLowerCase())
        .where((v) => v.isNotEmpty && v != 'unknown')
        .toSet();
    return set.length;
  }

  StatsRankItem _topRankItem(Iterable<String> values, String fallback) {
    final counts = <String, int>{};
    for (final v in values) {
      final key = v.trim().toLowerCase();
      if (key.isEmpty || key == 'unknown') continue;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (counts.isEmpty) return StatsRankItem(fallback, 0, 0.0);
    final entry = counts.entries.reduce((a, b) => a.value > b.value ? a : b);
    return StatsRankItem(entry.key, entry.value, entry.value / values.length);
  }

  String _generateId() => Uuid().v4();

  // Queue
  List<Music> get queueMusicList => _streamingMusic != null
      ? List<Music>.unmodifiable(_streamingQueue.isEmpty ? [_streamingMusic!] : _streamingQueue)
      : List<Music>.unmodifiable(_activeQueue.isNotEmpty ? _activeQueue : _musicList);
  int get currentQueuePosition => _currentIndex;

  Future<void> playMusicFromQueue(List<Music> queue, Music music,
      {String? playlistId}) async {
    debugPrint('[pvf] playMusicFromQueue: ${music.title} (${music.filePath})');
    
    // Ensure C++ bridge is initialized
    if (!CppCoreBridge.isBridgeInitialized()) {
      debugPrint('[pvf] CppCoreBridge not initialized, initializing now...');
      CppCoreBridge.initialize();
    }
    
    debugPrint('[pvf]   queue.length=${queue.length}, engineReady=${CppCoreBridge.isReady()}');
    if (playlistId != null) _currentPlaylistId = playlistId;
    final index = queue.indexWhere((m) => m.id == music.id);
    if (index == -1) {
      debugPrint('[pvf]   music.id=${music.id} NOT FOUND in queue!');
      return;
    }
    _activeQueue = List<Music>.from(queue);
    _streamingMusic = null;
    _streamingQueue = [];
    _currentIndex = index;
    _currentIndexNotifier.value = index;
    _currentMusicNotifier.value = music;
    debugPrint('[pvf]   _activeQueue set, _currentIndex=$index, calling play()');
    await play();
  }

  void addToQueue(String musicId) {
    // skipped: add to queue
  }

  void addAllToQueue(List<Music> musics) {
    // skipped: add all to queue
  }

  void moveQueueItem(int from, int to) {
    // skipped: move queue item
  }

  Future<void> replaceStreamingQueue(
    List<Music> queue,
    Music target, {
    Duration? startPosition,
    bool? shouldPlay,
  }) async {
    _streamingQueue = List<Music>.from(queue);
    _streamingMusic = target;
    if (startPosition != null) _position = startPosition;
    if (shouldPlay == true) {
      await play();
    } else {
      notifyListeners();
    }
  }

  // Lyrics
  Future<LyricsDocument?> loadLyricsDocumentForCurrent({
    bool searchOnline = false,
    String? explicitPath,
  }) async {
    final music = currentMusic;
    if (music == null) return null;

    final candidates = <String>[
      if (explicitPath != null) explicitPath,
      await _manualLyricsPathForMusic(music),
      await _manualPlainLyricsPathForMusic(music),
      if (music.filePath.isNotEmpty)
        '${music.filePath}.lrc',
      if (music.filePath.isNotEmpty)
        p.join(p.dirname(music.filePath),
            '${p.basenameWithoutExtension(music.filePath)}.lrc'),
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (!await file.exists()) continue;
      try {
        final raw = await file.readAsString();
        if (raw.trim().isEmpty) continue;
        final document = LyricsDocument.parse(raw, source: candidate);
        if (document.lines.isNotEmpty) return document;
      } catch (e) {
        debugPrint('Error reading lyrics: $e');
      }
    }

    if (searchOnline) {
      final doc = await searchLyricsForCurrentOnline();
      if (doc != null && doc.lines.isNotEmpty) {
        await saveLyricsForCurrent(doc.rawText);
      }
      return doc;
    }
    return null;
  }

  Future<LyricsDocument?> saveLyricsForCurrent(String lrcText) async {
    final music = currentMusic;
    if (music == null) return null;
    final path = await _manualLyricsPathForMusic(music);
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(lrcText);
      return LyricsDocument.parse(lrcText, source: path);
    } catch (e) {
      debugPrint('Error saving lyrics: $e');
    }
    return null;
  }

  Future<void> deleteLyricsForCurrent() async {
    final music = currentMusic;
    if (music == null) return;
    final path = await _manualLyricsPathForMusic(music);
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Error deleting lyrics: $e');
    }
    _currentLyrics = null;
    _lyricsError = null;
    _lyricsLoading = false;
    _syncAligner();
    notifyListeners();
  }

  Future<LyricsDocument?> searchLyricsForCurrentOnline() async {
    final music = currentMusic;
    if (music == null) {
      debugPrint('LyricsSearch: currentMusic is null, aborting');
      return null;
    }

    debugPrint('LyricsSearch: searching for "${music.title}" by "${music.artist}" '
        '(album="${music.album}", duration=${music.duration?.inSeconds}s)');

    final manager = LyricsManager();
    final request = ProviderSearchRequest(
      artist: music.artist,
      title: music.title,
      album: music.album,
      durationMs: music.duration?.inMilliseconds,
      youtubeId: await _resolveYoutubeIdForMusic(music),
    );

    final result = await manager.fetchLyrics(request);
    if (result != null) {
      debugPrint('LyricsSearch: ${result.providerName} found ${result.lyrics.length} lines (${result.type})');
      return result.toDocument();
    }

    debugPrint('LyricsSearch: all providers exhausted, no lyrics found');
    return null;
  }

  /// Resolves a real YouTube videoId for [music]. First tries to extract one
  /// from the track's file path / embedded link; if none exists, falls back to
  /// a YouTube search using the track metadata (title/artist/duration) so
  /// videoId-keyed providers (Cubey/Better Lyrics) get a real YouTube link.
  Future<String?> _resolveYoutubeIdForMusic(Music music) async {
    final extracted = _extractYoutubeId(music);
    if (extracted != null) {
      debugPrint('[LyricsSearch] Extracted YouTube videoId from link: $extracted');
      return extracted;
    }
    try {
      final searched = await YoutubeMusicService().searchVideoIdForMetadata(
        title: music.title,
        artist: music.artist,
        durationSeconds: music.duration?.inSeconds,
      );
      debugPrint('[LyricsSearch] Searched YouTube videoId for Cubey: $searched');
      return searched;
    } catch (e) {
      debugPrint('LyricsSearch: youtube metadata search failed: $e');
      return null;
    }
  }

  /// Extracts a YouTube videoId from a [Music] file path (youtube.com /
  /// youtu.be URL, or an 11-character video-ID filename). Null if none.
  String? _extractYoutubeId(Music music) {
    final path = music.filePath;
    if (path.contains('youtube.com') || path.contains('youtu.be')) {
      final uri = Uri.tryParse(path);
      if (uri != null) {
        if (uri.host.contains('youtu.be')) {
          return uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
        }
        return uri.queryParameters['v'];
      }
    }
    final fileName = path.split(RegExp(r'[/\\]')).last.split('.').first;
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(fileName)) return fileName;
    return null;
  }

  Future<List<LrclibLyrics>> searchLyricsResultsForCurrent({
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
  }) async {
    return LrcLibService.searchResults(
      trackName: title,
      artistName: artist,
      albumName: album,
      durationSeconds: durationSeconds,
    );
  }

  Future<LyricsDocument?> saveLyricsResultForCurrent(LrclibLyrics lyrics) async {
    final raw = lyrics.syncedLyrics ?? lyrics.plainLyrics;
    if (raw == null || raw.trim().isEmpty) return null;
    return saveLyricsForCurrent(raw);
  }

  Future<String?> editableLyricsForCurrent() async {
    final document = await loadLyricsDocumentForCurrent(searchOnline: false);
    return document?.rawText;
  }

  Future<void> keepOriginalLyricsTimingForCurrent(String rawLyrics) async {
    final music = currentMusic;
    if (music == null) return;
    final backupPath = await _manualLyricsTimingBackupPathForMusic(music);
    try {
      final file = File(backupPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(rawLyrics);
    } catch (e) {
      debugPrint('Error backing up lyrics: $e');
    }
  }

  Future<LyricsDocument?> restoreOriginalLyricsTimingForCurrent() async {
    final music = currentMusic;
    if (music == null) return null;
    final backupPath = await _manualLyricsTimingBackupPathForMusic(music);
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) return null;
    final raw = await backupFile.readAsString();
    return saveLyricsForCurrent(raw);
  }

  Future<void> saveLyricsToAudioFile(String rawLyrics) async {
    final music = currentMusic;
    if (music == null) return;
    final target = music.filePath;
    if (target.isEmpty) return;

    try {
      final success = CppCoreBridge.setLyrics(target, rawLyrics);
      if (!success) {
        debugPrint('LyricsEmbed: pvf_set_lyrics returned false for $target');
      }
    } catch (e) {
      debugPrint('LyricsEmbed: error embedding lyrics: $e');
    }
  }

  Future<String> _manualLyricsPathForMusic(Music music) async {
    final dir = await getPlayerVfDocumentsDirectory();
    return p.join(dir.path, 'lyrics', '${_safeLyricsFileToken(music)}.lrc');
  }

  Future<String> _manualPlainLyricsPathForMusic(Music music) async {
    final dir = await getPlayerVfDocumentsDirectory();
    return p.join(dir.path, 'lyrics', '${_safeLyricsFileToken(music)}.txt');
  }

  Future<String> _manualLyricsTimingBackupPathForMusic(Music music) async {
    final dir = await getPlayerVfDocumentsDirectory();
    return p.join(
        dir.path, 'lyrics', '${_safeLyricsFileToken(music)}.original.lrc');
  }

  String _safeLyricsFileToken(Music music) {
    final raw = '${music.artist} - ${music.title}';
    final token = raw.replaceAll(RegExp(r'[^A-Za-z0-9\u4e00-\u9fff]+'), '_');
    return token.isEmpty ? music.id : token;
  }

  // Audio Effects (proxied to C++)
  bool get isEffectsEnabled => true;
  bool get isEqualizerEnabled => false;
  void setEffectsEnabled(bool value) {
    // skipped: will be proxied to C++
  }

  void setEqualizerEnabled(bool value) {
    // skipped
  }

  void setEqualizerBand(int band, double value) {
    // skipped
  }

  void previewEqualizerBand(int band, double value) {
    // skipped
  }

  List<double> get currentEqBandValues => List.filled(10, 0.0);
  String get currentPreset => 'Normal';
  double get pitch => 1.0;
  double get speed => 1.0;
  double get reverb => 0.0;
  bool get supportsPitchControl => true;

  void setPitch(double value) {
    if (_usingFallbackPlayer && _fallbackPlayer != null) {
      _fallbackPlayer!.setPitch(value);
    } else {
      CppCoreBridge.setPitch(value);
    }
  }

  void setSpeed(double value) {
    if (_usingFallbackPlayer && _fallbackPlayer != null) {
      _fallbackPlayer!.setSpeed(value);
    } else {
      CppCoreBridge.setSpeed(value);
    }
  }

  void setReverb(double value) {
    // skipped
  }

  bool get useSongSpecificSettings => false;
  void setUseSongSpecificSettings(bool value) {}

  List<int> getEqualizerFrequencies() => const [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
  List<String> getEqualizerPresets() => const ['Flat', 'Normal', 'Pop', 'Rock', 'Jazz'];

  void setEqualizerPreset(String preset) {
    // skipped
  }

  void resetEqualizer() {
    // skipped
  }

  void resetAudioEffects() {
    // skipped
  }

  // DSP
  bool get dspEnabled => true;
  bool get dspLoudnessNormalizationEnabled => true;
  bool get dspLimiterEnabled => true;
  bool get dspCompressorEnabled => false;
  double get dspBass => 0.0;
  double get dspMid => 0.0;
  double get dspTreble => 0.0;

  void setDspEnabled(bool value) {}
  void setDspLoudnessNormalizationEnabled(bool value) {}
  void setDspLimiterEnabled(bool value) {}
  void setDspCompressorEnabled(bool value) {}
  void setDspTone({double? bass, double? mid, double? treble}) {}
  void resetDspTone() {}

  // Safe Ears
  bool get safeEarsEnabled => false;
  double get safeEarsMaxVolume => 72.0;

  Future<void> setSafeEarsEnabled(bool value) async {}
  Future<void> setSafeEarsMaxVolume(double value) async {}

  // Playback settings
  bool get rememberPlayback => _rememberPlayback;
  Future<void> setRememberPlayback(bool value) async {
    if (_rememberPlayback == value) return;
    _rememberPlayback = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberPlaybackKey, value);
    notifyListeners();
  }

  ValueNotifier<Duration> get songGapRemainingNotifier => ValueNotifier(Duration.zero);
  Future<void> setDecoderModes({required dynamic audio, required dynamic video}) async {}
  Future<void> setSongGapDuration(Duration duration) async {}

  // Streaming / YouTube
  Future<void> playStreamingMusic(Music music, {Duration? startPosition, bool shouldPlay = true}) async {
    _streamingMusic = music;
    await play();
  }

  Future<void> replaceStreamingMusic(Music music, {Duration? startPosition, bool shouldPlay = true}) async {
    _streamingMusic = music;
    notifyListeners();
  }

  // Video
  dynamic get videoController => null;
  Future<void> loadSubtitleFile(String path) async {}
  Future<void> loadSubtitleUrl(String url, {String? title}) async {}
  Future<void> disableSubtitles() async {}

  // Other
  void toggleShuffle() => setShuffle(!_isShuffle);
  void toggleRepeatMode() => setRepeatMode(!_isRepeatOne, _isRepeatAll);
  Future<void> previousTrack() async => previous();
  Future<void> restartCurrentTrack() async => seekTo(Duration.zero);
  Future<void> previousOrRestartShortcut() async {
    if (_position > const Duration(seconds: 3)) {
      await seekTo(Duration.zero);
    } else {
      await previous();
    }
  }

  Future<int> importWebFolderMusic([List? paths]) async {
    if (paths == null || paths.isEmpty) return 0;
    try {
      final musicList = await MusicScannerService.createMusicListFromPaths(
          paths.map((p) => p.toString()).toList());
      if (musicList.isEmpty) return 0;
      var added = 0;
      for (final music in musicList) {
        final exists =
            _musicList.any((m) => m.filePath == music.filePath);
        if (exists) continue;
        _musicList.add(music);
        added++;
      }
      if (added == 0) return 0;
      _invalidateDataCache();
      notifyListeners();
      await _saveLibrarySnapshot();
      return added;
    } catch (e) {
      debugPrint('Error importing web folder music: $e');
      return 0;
    }
  }

  Future<int> importSharedMusicFiles(
    List filePaths, {
    bool createBackup = true,
  }) async {
    if (filePaths.isEmpty) return 0;
    try {
      final musicList = await MusicScannerService.createMusicListFromPaths(
          filePaths.map((p) => p.toString()).toList());
      if (musicList.isEmpty) return 0;
      var added = 0;
      for (final music in musicList) {
        final exists =
            _musicList.any((m) => m.filePath == music.filePath);
        if (exists) continue;
        _musicList.add(music);
        added++;
      }
      if (added == 0) return 0;
      _invalidateDataCache();
      notifyListeners();
      await _saveLibrarySnapshot();
      return added;
    } catch (e) {
      debugPrint('Error importing shared music files: $e');
      return 0;
    }
  }

  void clearCache() {
    // skipped
  }

  Future<void> playPlaylist(String playlistId) async {
    final musics = getMusicListForPlaylist(playlistId);
    if (musics.isEmpty) return;
    _musicList = musics;
    _currentIndex = 0;
    await play();
  }

  void removeMusicFromPlaylist(String playlistId, String musicId) {
    final playlist = _playlists.firstWhereOrNull((p) => p.id == playlistId);
    if (playlist != null) {
      playlist.musicIds.remove(musicId);
      notifyListeners();
    }
  }

  void renamePlaylist(String playlistId, String newName) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index] =
          _playlists[index].copyWith(name: newName, updatedAt: DateTime.now());
      notifyListeners();
    }
  }

  Future<void> updateMusicCover(String id, String coverPath) async {
    final index = _musicList.indexWhere((m) => m.id == id);
    if (index != -1) {
      _musicList[index] = _musicList[index].copyWith(coverPath: coverPath);
      notifyListeners();
    }
  }

  bool isFavorite(String id) {
    return _musicList.firstWhereOrNull((m) => m.id == id)?.isFavorite ?? false;
  }

  static double _ratio(int part, int total) => total > 0 ? part / total : 0.0;
}

extension ListFirstWhereOrNullExtension<E> on List<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
