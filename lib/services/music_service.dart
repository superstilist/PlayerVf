import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:crypto/crypto.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lyrics_model.dart';
import '../models/music_model.dart';
import '../models/playlist_model.dart';
import '../models/settings_model.dart';
import 'music_scanner_service.dart';
import 'player_audio_handler.dart';
import 'web_folder_picker.dart';

class MusicService extends ChangeNotifier with WidgetsBindingObserver {
  static const String _playbackStateKey = 'playback_state';
  static const String _rememberPlaybackKey = 'remember_playback_enabled';
  static const String _librarySnapshotKey = 'music_library_snapshot';
  static const String _effectsEnabledKey = 'master_eff';
  static const String _equalizerEnabledKey = 'eq_enabled';
  static const String _equalizerPresetKey = 'eq_preset';
  static const String _globalEqKey = 'glob_eq';
  static const String _pitchKey = 'pitch_eff';
  static const String _speedKey = 'speed_eff';
  static const String _reverbKey = 'reverb_eff';
  static const String _songSettingsKey = 'song_eff_map';
  static const String _songSpecificSettingsKey = 'song_specific_eff';
  static const Duration _manualCrossfadeDuration = Duration(milliseconds: 340);
  static const Duration _singlePlayerFadeOutDuration =
      Duration(milliseconds: 180);
  static const Duration _singlePlayerFadeInDuration =
      Duration(milliseconds: 240);
  static const Duration _playFadeInDuration = Duration(milliseconds: 220);
  static const Duration _pauseFadeOutDuration = Duration(milliseconds: 180);
  List<Music> _musicList = [];
  Music? _streamingMusic;
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final PlayerAudioHandler _audioHandler;
  late Player _mediaPlayer;
  VideoController? _videoController;
  bool _videoControllerReady = false;
  double _volume = 100.0;

  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _playingNotifier = ValueNotifier(false);
  final ValueNotifier<double> _volumeNotifier = ValueNotifier(100.0);

  bool _isInitialized = false;
  DateTime _lastPositionUpdate = DateTime.now();
  DateTime _lastExternalPlaybackUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPlaybackPersistUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _suppressPositionUpdatesForTrackChange = false;
  Timer? _saveSettingsTimer;
  Timer? _savePlaybackTimer;

  List<String> _activeQueueIds = [];
  List<String> _shuffledQueueIds = [];
  bool _isShuffle = false;
  bool _isLoadingSystemMusic = false;
  int _systemMusicCount = 0;

  List<Music> _cachedDailyMix = [];
  List<Music> _cachedMostListened = [];
  List<Music> _cachedEarlyListened = [];
  List<Playlist> _playlists = [];
  String? _currentPlaylistId;
  bool _isRepeatOne = false;
  bool _isRepeatAll = true;
  bool _rememberPlayback = true;
  bool _hasRestoredPlayback = false;
  bool _isPlaybackCommandActive = false;
  Future<void> Function()? _pendingPlaybackCommand;
  String? _completedTrackId;
  Map<String, dynamic>? _pendingPlaybackState;
  String? _openedMusicId;
  String? _resumeTrackId;
  Duration _resumePosition = Duration.zero;
  bool _shouldResumeCurrentTrack = false;
  bool _hasVideoTrack = false;

  bool _isEffectsEnabled = true;
  bool _isEqualizerEnabled = false;
  List<double> _globalEqValues = List.filled(10, 0.0);
  String _currentPreset = 'Normal';
  double _pitch = 1.0;
  double _speed = 1.0;
  double _reverb = 0.0;
  double _effectsVolumeFactor = 1.0;
  Map<String, dynamic> _songSettings = {};
  bool _useSongSpecificSettings = false;

  bool _isUpdatingEffects = false;
  bool _hasPendingUpdate = false;
  bool _supportsPitchControl = true;
  Timer? _effectsUpdateTimer;
  int _effectsUpdateGeneration = 0;
  String? _lastNativeAudioFilterKey;
  double? _lastLoggedPcEqVolumeFactor;
  DecoderMode _audioDecoderMode = DecoderMode.auto;
  DecoderMode _videoDecoderMode = DecoderMode.auto;
  bool _isInternalVolumeChange = false;
  int _internalVolumeChangeDepth = 0;
  int _audioTransitionGeneration = 0;
  int _volumeChangeGeneration = 0;
  bool _usingNativeWindowsAudio = false;
  bool _windowsNativeAudioAvailable = true;
  Duration _songGapDuration = Duration.zero;
  final List<StreamSubscription> _playerSubscriptions = [];
  Player? _retiringPlayer;
  List<String>? _lastUsedPaths;

  static const List<int> _eqFreqs = [
    31,
    62,
    125,
    250,
    500,
    1000,
    2000,
    4000,
    8000,
    16000
  ];
  static const Map<String, List<double>> _eqPresets = {
    'Flat': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Normal': [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Pop': [-1, 2, 4, 5, 4, 2, 0, -1, -2, -3],
    'Rock': [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
    'Jazz': [3, 2, 1, 2, -2, -2, 0, 1, 2, 3],
    'Classical': [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
    'Bass Boost': [6, 5, 4, 3, 1, 0, 0, 0, 0, 0],
    'Treble Boost': [0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
    'Electronic': [-2, 0, 2, 4, 5, 4, 2, 0, -1, -2],
    'Hip Hop': [5, 4, 3, 1, -1, -2, 0, 1, 2, 3],
    'Acoustic': [3, 2, 1, 1, 2, 2, 3, 3, 2, 2],
    'Dance': [5, 6, 4, 1, 0, 2, 4, 5, 4, 3],
    'Metal': [5, 4, 3, 1, -1, -1, 1, 3, 5, 6],
    'R&B': [4, 5, 4, 2, -1, 0, 1, 2, 3, 4],
    'Vocal': [-2, -1, 0, 3, 5, 5, 3, 1, -1, -2],
    'Podcast': [-4, -3, -1, 2, 5, 5, 3, 0, -2, -4],
    'Loudness': [6, 4, 2, 0, -1, 0, 2, 3, 5, 6],
    'Deep': [7, 6, 5, 3, 1, -1, -2, -2, -1, 0],
    'Bright': [-2, -1, 0, 1, 2, 3, 4, 5, 6, 7],
    'Soft': [2, 1, 0, -1, -2, -1, 0, 1, 2, 3],
    'Movie': [5, 4, 2, 0, -2, 0, 2, 4, 5, 6],
  };

  MusicService() {
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
    _mediaPlayer = Player();
    _bindPlayer(_mediaPlayer);
    _initializeAsync();
  }

  Future<void> _initVideoController() async {
    try {
      _videoController = VideoController(
        _mediaPlayer,
        configuration: VideoControllerConfiguration(
          hwdec: _videoHwdecValue(),
          enableHardwareAcceleration: _videoDecoderMode != DecoderMode.software,
        ),
      );
      _videoControllerReady = true;
      notifyListeners();
    } catch (e) {
      debugPrint('VideoController not available on this platform: $e');
      _videoControllerReady = false;
    }
  }

  void _bindPlayer(Player player) {
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _playerSubscriptions.clear();
    _mediaPlayer = player;
    _initPlayer();
  }

  Future<void> _ensureVideoControllerForCurrentTrack() async {
    if (!_hasVideoTrack) {
      _videoController = null;
      _videoControllerReady = false;
      return;
    }
    if (_videoControllerReady && _videoController?.player == _mediaPlayer) {
      return;
    }
    await _initVideoController();
  }

  Future<void> _initializeAsync() async {
    await _loadSettingsAsync();
    await _loadDecoderSettingsAsync();
    await _loadLibrarySnapshotAsync();
    _isInitialized = true;
    notifyListeners();
    unawaited(_refreshLibraryAfterFirstFrame());
  }

  Future<void> _refreshLibraryAfterFirstFrame() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (_isLoadingSystemMusic) return;
    await loadSystemMusic(clearExisting: true);
  }

  void _initPlayer() {
    final player = _mediaPlayer;

    _playerSubscriptions.add(player.stream.position.listen((pos) {
      if (_suppressPositionUpdatesForTrackChange) return;

      final now = DateTime.now();
      if (now.difference(_lastPositionUpdate).inMilliseconds > 90) {
        _position = pos;
        _positionNotifier.value = pos;
        _lastPositionUpdate = now;
      }

      if (now.difference(_lastExternalPlaybackUpdate).inMilliseconds > 350) {
        _lastExternalPlaybackUpdate = now;
        _audioHandler.setExternalPlaybackState(
          playing: _isPlaying,
          position: _position,
          duration: _duration,
        );
      }

      if (now.difference(_lastPlaybackPersistUpdate).inMilliseconds > 1200) {
        _lastPlaybackPersistUpdate = now;
        _savePlaybackDebounced();
      }
    }));

    _playerSubscriptions.add(player.stream.duration.listen((dur) {
      final stableDuration =
          dur > Duration.zero ? dur : currentMusic?.duration ?? Duration.zero;
      _duration = stableDuration;
      _durationNotifier.value = _duration;
      _cacheCurrentTrackDuration(stableDuration);
      _audioHandler.setExternalPlaybackState(
        playing: _isPlaying,
        position: _position,
        duration: _duration,
      );
    }));

    _playerSubscriptions.add(player.stream.playing.listen((state) {
      _isPlaying = state;
      _playingNotifier.value = state;
      _audioHandler.setExternalPlaybackState(
        playing: state,
        position: _position,
        duration: _duration,
      );
      _savePlaybackDebounced();
      notifyListeners();
    }));

    _playerSubscriptions.add(player.stream.completed.listen((done) {
      if (!done) return;
      unawaited(_handleBackendCompleted());
    }));

    _playerSubscriptions.add(player.stream.volume.listen((vol) {
      if (_isInternalVolumeChange || _internalVolumeChangeDepth > 0) return;
      _volume = vol;
      _volumeNotifier.value = vol;
    }));

    _playerSubscriptions.add(_audioHandler.positionStream.listen((pos) {
      if (!_usingNativeWindowsAudio || _suppressPositionUpdatesForTrackChange) {
        return;
      }
      final now = DateTime.now();
      if (now.difference(_lastPositionUpdate).inMilliseconds > 90) {
        _position = pos;
        _positionNotifier.value = pos;
        _lastPositionUpdate = now;
      }
      if (now.difference(_lastPlaybackPersistUpdate).inMilliseconds > 1200) {
        _lastPlaybackPersistUpdate = now;
        _savePlaybackDebounced();
      }
    }));

    _playerSubscriptions.add(_audioHandler.durationStream.listen((dur) {
      if (!_usingNativeWindowsAudio) return;
      final stableDuration =
          dur != null && dur > Duration.zero ? dur : currentMusic?.duration;
      if (stableDuration == null) return;
      _duration = stableDuration;
      _durationNotifier.value = stableDuration;
      _cacheCurrentTrackDuration(stableDuration);
    }));

    _playerSubscriptions.add(_audioHandler.playingStream.listen((state) {
      if (!_usingNativeWindowsAudio) return;
      _isPlaying = state;
      _playingNotifier.value = state;
      _savePlaybackDebounced();
      notifyListeners();
    }));
  }

  void _cacheCurrentTrackDuration(Duration duration) {
    if (duration <= Duration.zero) return;
    final music = currentMusic;
    if (music == null) return;

    final oldDuration = music.duration;
    if (oldDuration != null &&
        (oldDuration - duration).inMilliseconds.abs() < 1000) {
      return;
    }

    music.duration = duration;
    _durationNotifier.value = duration;
    unawaited(_saveLibrarySnapshot());

    if (!kIsWeb &&
        !music.filePath.startsWith('http://') &&
        !music.filePath.startsWith('https://') &&
        !music.filePath.startsWith('blob:')) {
      unawaited(MusicScannerService.cacheMusic(music, File(music.filePath)));
    }
  }

  Future<void> _handleSystemPlay() async {
    if (currentMusic == null && _musicList.isNotEmpty) {
      await play();
      return;
    }
    if (!_isPlaying) {
      await _runPlaybackCommand(
        _togglePlayPauseInternal,
        dropIfActive: true,
      );
    }
  }

  Future<void> _handleSystemTogglePlayPause() async {
    if (currentMusic == null && _musicList.isNotEmpty) {
      await play();
      return;
    }
    await _runPlaybackCommand(
      _togglePlayPauseInternal,
      dropIfActive: true,
    );
  }

  Future<void> _handleSystemPause() async {
    if (_isPlaying) {
      await _runPlaybackCommand(
        _togglePlayPauseInternal,
        dropIfActive: true,
      );
    }
  }

  Future<void> _handleSystemNext() async => _runPlaybackCommand(_nextInternal);

  Future<void> _handleSystemPrevious() async =>
      _runPlaybackCommand(() => _previousInternal(forcePrevious: true));

  Future<void> _handleSystemSeek(Duration position) async => seekTo(position);

  Future<void> _handleSystemCompleted() async => _handleBackendCompleted();

  List<Music> get musicList => _musicList;
  Music? get currentMusic => _streamingMusic ?? _libraryCurrentMusic;
  Music? get _libraryCurrentMusic =>
      _musicList.isNotEmpty && _currentIndex < _musicList.length
          ? _musicList[_currentIndex]
          : null;
  String get playbackSourceLabel {
    final music = currentMusic;
    if (music == null) return 'Ready';

    final genre = music.genre.toLowerCase();
    final path = music.filePath.toLowerCase();
    if (genre.contains('youtube music')) return 'YouTube Music';
    if (genre.contains('web') || path.startsWith('blob:')) {
      return 'Web folder';
    }
    if (kIsWeb) return 'Web player';
    if (Platform.isAndroid) return 'Android native audio';
    if (Platform.isWindows) return 'Windows native audio';
    if (Platform.isMacOS) return 'macOS audio';
    if (Platform.isLinux) return 'Linux audio';
    if (Platform.isIOS) return 'iOS audio';
    return 'Local library';
  }

  String get topBarNowPlayingLabel {
    final music = currentMusic;
    if (music == null) return 'Ready to play';
    return '${isPlaying ? 'Playing' : 'Paused'} from $playbackSourceLabel';
  }

  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;
  ValueNotifier<Duration> get durationNotifier => _durationNotifier;
  ValueNotifier<bool> get playingNotifier => _playingNotifier;
  ValueNotifier<double> get volumeNotifier => _volumeNotifier;
  double get volume => _volume;
  bool get isLoadingSystemMusic => _isLoadingSystemMusic;
  int get systemMusicCount => _systemMusicCount;
  List<Playlist> get playlists => _playlists;
  bool get isShuffle => _isShuffle;
  VideoController? get videoController => _videoController;
  bool get videoControllerReady => _videoControllerReady;
  bool get hasVideoTrack => _hasVideoTrack;
  DecoderMode get audioDecoderMode => _audioDecoderMode;
  DecoderMode get videoDecoderMode => _videoDecoderMode;

  /// Returns true if the current media should be treated as a video.
  /// Prioritizes known audio extensions to ensure music files use the dedicated music player interface.
  bool get isCurrentMediaVideo {
    final music = currentMusic;
    if (music == null || !_videoControllerReady) return false;
    return _isVideoTrack(music);
  }

  bool _isVideoTrack(Music music) {
    if (music.genre == 'YouTube Music Video') return true;
    if (music.genre == 'YouTube Music') return false;

    final ext = music.filePath.split('.').last.toLowerCase();
    if (['mp3', 'm4a', 'flac', 'wav', 'ogg', 'aac', 'wma'].contains(ext)) {
      return false;
    }
    if (['mp4', 'mkv', 'webm', 'avi', 'mov'].contains(ext)) return true;
    return _hasVideoTrack;
  }

  String _metadataTitle(Music track) {
    final title = track.title.trim();
    if (title.isNotEmpty) return title;

    final uri = Uri.tryParse(track.filePath);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final lastSegment = uri.pathSegments.last.trim();
      if (lastSegment.isNotEmpty) return Uri.decodeComponent(lastSegment);
    }

    return 'Unknown track';
  }

  String _metadataArtist(Music track) {
    final artist = track.artist.trim();
    return artist.isEmpty ? 'PlayerVf' : artist;
  }

  bool get isRepeatOne => _isRepeatOne;
  bool get isRepeatAll => _isRepeatAll;
  bool get isEffectsEnabled => _isEffectsEnabled;
  bool get isEqualizerEnabled => _isEqualizerEnabled;
  String get currentPreset => _currentPreset;
  double get pitch => _pitch;
  double get speed => _speed;
  double get reverb => _reverb;
  bool get useSongSpecificSettings => _useSongSpecificSettings;
  String? get currentPlaylistId => _currentPlaylistId;
  bool get isInitialized => _isInitialized;
  bool get rememberPlayback => _rememberPlayback;
  bool get supportsPitchControl => _supportsPitchControl;
  List<Music> get queueMusicList => _streamingMusic != null
      ? [_streamingMusic!]
      : _resolveMusicIds(_playbackOrderIds());
  int get currentQueuePosition {
    if (_streamingMusic != null) return 0;
    final current = currentMusic;
    if (current == null) return -1;
    return _playbackOrderIds().indexOf(current.id);
  }

  List<double> get currentEqBandValues {
    if (_useSongSpecificSettings && currentMusic != null) {
      final song = _songSettings[currentMusic!.id];
      if (song != null && song['eq'] != null) {
        return _normalizeEqValues(
          List<double>.from(song['eq'].map((e) => (e as num).toDouble())),
        );
      }
    }
    return _globalEqValues;
  }

  List<Music> get favoriteMusicList =>
      _musicList.where((m) => m.isFavorite).toList();
  List<Playlist> get systemPlaylists => [
        Playlist(
            id: 'favorites',
            name: 'Favorites',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        Playlist(
            id: 'most_listened',
            name: 'Most Listened',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        Playlist(
            id: 'early_listened',
            name: 'Early Listened',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
        Playlist(
            id: 'daily_mix',
            name: 'Daily Mix',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now()),
      ];
  List<Playlist> get allPlaylists => [...systemPlaylists, ..._playlists];

  set currentIndex(int index) {
    if (index >= 0 && index < _musicList.length) {
      final nextTrackId = _musicList[index].id;
      if (nextTrackId != currentMusic?.id) {
        _clearResumeState(keepOpenedTrack: false);
      }
      _currentIndex = index;
      _savePlaybackDebounced();
      notifyListeners();
    }
  }

  set currentPlaylistId(String? id) {
    _currentPlaylistId = id;
    _savePlaybackDebounced();
    notifyListeners();
  }

  void setEffectsEnabled(bool value) {
    _isEffectsEnabled = value;
    notifyListeners();
    _scheduleUpdate(delay: Duration.zero);
    _saveDebounced();
  }

  void setEqualizerEnabled(bool value) {
    _isEqualizerEnabled = value;
    if (value) {
      _isEffectsEnabled = true;
    }
    notifyListeners();
    _scheduleUpdate(delay: Duration.zero);
    _saveDebounced();
  }

  void setUseSongSpecificSettings(bool value) {
    _useSongSpecificSettings = value;
    notifyListeners();
    _scheduleUpdate();
    _saveDebounced();
  }

  void setPitch(double value) {
    _pitch = value;
    _isEffectsEnabled = true;
    notifyListeners();
    _scheduleUpdate();
    _saveDebounced();
  }

  void setSpeed(double value) {
    _speed = value;
    _isEffectsEnabled = true;
    notifyListeners();
    _scheduleUpdate();
    _saveDebounced();
  }

  void setReverb(double value) {
    _reverb = value;
    if (value > 0) _isEffectsEnabled = true;
    notifyListeners();
    _scheduleUpdate();
    _saveDebounced();
  }

  void setEqualizerBand(int band, double value) {
    if (band < 0 || band >= _globalEqValues.length) return;
    value = _normalizeEqGain(value);
    _isEqualizerEnabled = true;
    _isEffectsEnabled = true;

    if (_useSongSpecificSettings && currentMusic != null) {
      final id = currentMusic!.id;
      _songSettings[id] ??= {'eq': List.from(_globalEqValues)};
      _songSettings[id]['eq'][band] = value;
    } else {
      _globalEqValues[band] = value;
      _currentPreset = 'Custom';
    }

    notifyListeners();
    _scheduleUpdate(delay: Duration.zero);
    _saveDebounced();
  }

  void previewEqualizerBand(int band, double value) {
    if (band < 0 || band >= _globalEqValues.length) return;
    value = _normalizeEqGain(value);
    _isEqualizerEnabled = true;
    _isEffectsEnabled = true;

    if (_useSongSpecificSettings && currentMusic != null) {
      final id = currentMusic!.id;
      _songSettings[id] ??= {'eq': List.from(_globalEqValues)};
      _songSettings[id]['eq'][band] = value;
    } else {
      _globalEqValues[band] = value;
      _currentPreset = 'Custom';
    }

    notifyListeners();
    _scheduleUpdate(delay: Duration.zero);
  }

  double _normalizeEqGain(double value) =>
      double.parse(value.clamp(-10.0, 10.0).toStringAsFixed(1));

  List<double> _normalizeEqValues(List<double> values) {
    final normalized = List<double>.from(values.take(_eqFreqs.length))
        .map(_normalizeEqGain)
        .toList();
    while (normalized.length < _eqFreqs.length) {
      normalized.add(0.0);
    }
    return normalized;
  }

  void setEqualizerPreset(String preset) {
    _currentPreset = preset;
    _isEqualizerEnabled = true;
    _isEffectsEnabled = true;

    if (_eqPresets.containsKey(preset)) {
      final values = List<double>.from(_eqPresets[preset]!);
      if (_useSongSpecificSettings && currentMusic != null) {
        _songSettings[currentMusic!.id] ??= {};
        _songSettings[currentMusic!.id]['eq'] = values;
      } else {
        _globalEqValues = values;
      }
    }

    notifyListeners();
    _scheduleUpdate(delay: Duration.zero);
    _saveDebounced();
  }

  void resetEqualizer() {
    _applyFlatEqualizerPreset();
    _isEqualizerEnabled = false;
    notifyListeners();
    _scheduleUpdate(delay: Duration.zero);
    _saveDebounced();
  }

  void _applyFlatEqualizerPreset({bool forceGlobal = false}) {
    _currentPreset = 'Flat';
    final values = List<double>.from(_eqPresets['Flat']!);
    if (!forceGlobal && _useSongSpecificSettings && currentMusic != null) {
      _songSettings[currentMusic!.id] ??= {};
      _songSettings[currentMusic!.id]['eq'] = values;
    } else {
      _globalEqValues = values;
    }
  }

  void resetAudioEffects() {
    _isEffectsEnabled = true;
    _isEqualizerEnabled = false;
    _pitch = 1.0;
    _speed = 1.0;
    _reverb = 0.0;
    if (_useSongSpecificSettings && currentMusic != null) {
      _songSettings.remove(currentMusic!.id);
    }
    _applyFlatEqualizerPreset(forceGlobal: true);
    notifyListeners();
    _scheduleUpdate();
    _saveDebounced();
  }

  void setHighFidelityPlayback() {
    _isEffectsEnabled = false;
    _isEqualizerEnabled = false;
    _pitch = 1.0;
    _speed = 1.0;
    _reverb = 0.0;
    _applyFlatEqualizerPreset(forceGlobal: true);
    notifyListeners();
    _scheduleUpdate(delay: Duration.zero);
    _saveDebounced();
  }

  void _scheduleUpdate({Duration delay = const Duration(milliseconds: 90)}) {
    _effectsUpdateTimer?.cancel();
    if (delay == Duration.zero) {
      Future.microtask(_applyScheduledEffects);
      return;
    }
    _effectsUpdateTimer = Timer(delay, _applyScheduledEffects);
  }

  Future<void> _applyScheduledEffects() async {
    if (_isUpdatingEffects) {
      _hasPendingUpdate = true;
      return;
    }

    _isUpdatingEffects = true;
    _hasPendingUpdate = false;
    final generation = ++_effectsUpdateGeneration;
    try {
      await _applyAudioEffects(_mediaPlayer, generation: generation);
      if (_usingNativeWindowsAudio) {
        await _applyNativeWindowsAudioEffects();
      }
    } catch (e) {
      debugPrint('Error updating effects: $e');
    } finally {
      _isUpdatingEffects = false;
      if (_hasPendingUpdate) {
        _scheduleUpdate();
      }
    }
  }

  Future<void> _applyAudioEffects(Player player, {int? generation}) async {
    if (generation != null && generation != _effectsUpdateGeneration) return;

    final native = player.platform;
    final filter = native is NativePlayer ? _buildAudioFilter() : '';

    await player.setRate(_isEffectsEnabled ? _speed : 1.0);
    if (_supportsPitchControl) {
      try {
        if (generation != null && generation != _effectsUpdateGeneration) {
          return;
        }
        await player.setPitch(_isEffectsEnabled ? _pitch : 1.0);
      } catch (e) {
        _supportsPitchControl = false;
        debugPrint('Pitch control is not supported on this platform: $e');
      }
    }

    if (generation != null && generation != _effectsUpdateGeneration) return;
    if (native is NativePlayer) {
      await _setNativeAudioFilter(native, filter);
    }
    if (generation != null && generation != _effectsUpdateGeneration) return;

    final nextVolumeFactor = _buildFallbackEqVolumeFactor();
    final shouldForcePcEqVolume =
        !kIsWeb && Platform.isWindows && _isEffectsEnabled;
    if (shouldForcePcEqVolume ||
        (nextVolumeFactor - _effectsVolumeFactor).abs() > 0.005) {
      _effectsVolumeFactor = nextVolumeFactor;
      await _setPlayerVolume(player, _volume);
      _logPcEqVolumeFactorIfNeeded(nextVolumeFactor);
    }
  }

  String _buildAudioFilter() {
    final parts = <String>[];
    final hasEqualizer = _isEffectsEnabled && _isEqualizerEnabled;
    final hasReverb = _isEffectsEnabled && _reverb > 0;

    if (!hasEqualizer && !hasReverb) {
      return '';
    }

    if (hasEqualizer) {
      final eqValues = currentEqBandValues;
      parts.add(_buildEqHeadroomFilter(eqValues));
      parts.addAll(_buildEqualizerFilterParts(eqValues));
    }

    if (hasReverb) {
      parts.add(
          'aecho=0.8:0.88:${(_reverb * 60).toInt() + 20}:${_reverb * 0.3}');
      parts.add(
          'freeverb=roomsize=${0.7 + (_reverb * 0.25)}:damp=${0.2 + (1.0 - _reverb) * 0.5}:wet=${_reverb * 0.8}:dry=${1.0 - (_reverb * 0.5)}:width=1.0');
      parts.add('extrastereo=m=${1.0 + _reverb * 1.5}');
    }

    parts.add('alimiter=limit=0.96');
    return parts.join(',');
  }

  String _buildEqHeadroomFilter(List<double> values) {
    final strongestBoost = values.fold<double>(
      0.0,
      (maxValue, value) => max(maxValue, value),
    );
    final headroomDb = -(strongestBoost * 0.58).clamp(0.0, 7.0);
    return 'volume=${headroomDb.toStringAsFixed(2)}dB';
  }

  List<String> _buildEqualizerFilterParts(List<double> values) {
    return List.generate(_eqFreqs.length, (index) {
      final value = values[index].clamp(-10.0, 10.0);
      final gain = value.toStringAsFixed(1);
      return 'equalizer=f=${_eqFreqs[index]}:width_type=o:width=1.2:g=$gain';
    });
  }

  double _buildFallbackEqVolumeFactor() {
    if (!_isEffectsEnabled || !_isEqualizerEnabled) return 1.0;
    final values = currentEqBandValues;
    final strongestBoost = values.fold<double>(
      0.0,
      (maxValue, value) => max(maxValue, value),
    );
    if (strongestBoost <= 0) return 1.0;

    final headroomDb = -(strongestBoost * 0.58).clamp(0.0, 7.0);
    return pow(10, headroomDb / 20).clamp(0.45, 1.0).toDouble();
  }

  void _logPcEqVolumeFactorIfNeeded(double factor) {
    if (kIsWeb || !Platform.isWindows) return;
    final previous = _lastLoggedPcEqVolumeFactor;
    if (previous != null && (previous - factor).abs() < 0.02) return;
    _lastLoggedPcEqVolumeFactor = factor;
    debugPrint(
        'Windows PC equalizer output factor: ${factor.toStringAsFixed(2)}');
  }

  Future<void> _applyNativeWindowsAudioEffects() async {
    _effectsVolumeFactor = _buildFallbackEqVolumeFactor();
    await _audioHandler.player.setSpeed(_isEffectsEnabled ? _speed : 1.0);
    await _audioHandler.setVolumeFromService(
      _effectiveBackendVolume(_volume) / 100.0,
    );
  }

  Future<bool> _setNativeAudioFilter(NativePlayer native, String filter) async {
    final lavfiValue = filter.isEmpty ? '' : _mpvLavfiAudioFilter(filter);
    final filterKey = lavfiValue;
    if (_lastNativeAudioFilterKey == filterKey) return true;
    var applied = false;
    var readback = '';
    if (filter.isEmpty) {
      applied = await _setNativeAudioFilterByCommand(native, '');
      applied = applied || await _setNativePlayerProperty(native, 'af', '');
    } else {
      applied = await _setNativeAudioFilterByCommand(native, lavfiValue);
      readback = applied ? await _getNativePlayerProperty(native, 'af') : '';
      if (!readback.contains('equalizer')) {
        applied = await _setNativePlayerProperty(native, 'af', lavfiValue);
        readback = applied ? await _getNativePlayerProperty(native, 'af') : '';
      }
    }
    if (applied && !kIsWeb && Platform.isWindows) {
      _lastNativeAudioFilterKey = filterKey;
      debugPrint(filter.isEmpty
          ? 'Windows equalizer filter cleared.'
          : 'Windows equalizer filter applied: ${readback.isEmpty ? lavfiValue : readback}');
    }
    return applied;
  }

  String _mpvLavfiAudioFilter(String filter) {
    final escaped = filter.replaceAll(r'\', r'\\').replaceAll(']', r'\]');
    return 'lavfi=[$escaped]';
  }

  Future<bool> _setNativeAudioFilterByCommand(
      NativePlayer native, String value) async {
    try {
      if (value.isEmpty) {
        await native.command(const ['af', 'clr']);
      } else {
        await native.command(['af', 'set', '@playervf_eq:$value']);
      }
      return true;
    } catch (_) {
      try {
        if (value.isEmpty) {
          await native.command(const ['af', 'clr']);
        } else {
          await native.command(const ['af', 'clr']);
          await native.command(['af', 'add', '@playervf_eq:$value']);
        }
        return true;
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> _setNativePlayerProperty(
      NativePlayer native, String property, String value) async {
    try {
      await (native as dynamic).setProperty(property, value);
      return true;
    } catch (_) {
      // Not every platform/backend exposes mpv properties.
      return false;
    }
  }

  Future<String> _getNativePlayerProperty(
      NativePlayer native, String property) async {
    try {
      return await native.getProperty(property);
    } catch (_) {
      return '';
    }
  }

  Future<void> setDecoderModes({
    required DecoderMode audio,
    required DecoderMode video,
  }) async {
    _audioDecoderMode = audio;
    _videoDecoderMode = video;
    await _applyDecoderSettings(_mediaPlayer);
    unawaited(_initVideoController());
    notifyListeners();
  }

  Future<void> _loadDecoderSettingsAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _audioDecoderMode = _decoderModeFromIndex(
          prefs.getInt(SettingsModel.audioDecoderModeKey));
      _videoDecoderMode = _decoderModeFromIndex(
          prefs.getInt(SettingsModel.videoDecoderModeKey));
    } catch (e) {
      debugPrint('Error loading decoder settings: $e');
    }
  }

  DecoderMode _decoderModeFromIndex(int? index) {
    if (index == null || index < 0 || index >= DecoderMode.values.length) {
      return DecoderMode.auto;
    }
    return DecoderMode.values[index];
  }

  Future<void> _applyDecoderSettings(Player player) async {
    final native = player.platform;
    if (native is! NativePlayer) return;
    await _setNativePlayerProperty(native, 'hwdec', _videoHwdecValue());
    await _setNativePlayerProperty(
      native,
      'vd-lavc-software-fallback',
      _videoDecoderMode == DecoderMode.hardware ? 'no' : 'yes',
    );
    await _setNativePlayerProperty(
      native,
      'ad-lavc-threads',
      _audioDecoderMode == DecoderMode.software ? '1' : '0',
    );
  }

  String _videoHwdecValue() {
    switch (_videoDecoderMode) {
      case DecoderMode.hardware:
        return 'auto-safe';
      case DecoderMode.software:
        return 'no';
      case DecoderMode.auto:
        return 'auto-safe';
    }
  }

  Future<void> loadSubtitleFile(String path) async {
    if (path.trim().isEmpty) return;
    await _mediaPlayer.setSubtitleTrack(
      SubtitleTrack.uri(
        Uri.file(path).toString(),
        title: p.basename(path),
      ),
    );
  }

  Future<void> loadSubtitleUrl(String url, {String? title}) async {
    final normalized = url.trim();
    if (normalized.isEmpty) return;
    await _mediaPlayer.setSubtitleTrack(
      SubtitleTrack.uri(
        normalized,
        title: title?.trim().isNotEmpty == true ? title!.trim() : 'Subtitles',
      ),
    );
  }

  Future<void> disableSubtitles() async {
    await _mediaPlayer.setSubtitleTrack(SubtitleTrack.no());
  }

  Future<void> _applySidecarSubtitleIfAvailable(
      Player player, String mediaPath) async {
    if (kIsWeb) return;
    for (final candidate in _subtitleSidecarCandidates(mediaPath)) {
      final file = File(candidate);
      if (!await file.exists()) continue;
      await player.setSubtitleTrack(
        SubtitleTrack.uri(
          Uri.file(candidate).toString(),
          title: p.basename(candidate),
        ),
      );
      return;
    }
  }

  List<String> _subtitleSidecarCandidates(String mediaPath) {
    final dir = p.dirname(mediaPath);
    final name = p.basenameWithoutExtension(mediaPath);
    return [
      p.join(dir, '$name.srt'),
      p.join(dir, '$name.vtt'),
      p.join(dir, '$name.ass'),
      p.join(dir, '$name.ssa'),
    ];
  }

  Future<String?> loadLyricsForCurrent({String? explicitPath}) async {
    final document =
        await loadLyricsDocumentForCurrent(explicitPath: explicitPath);
    return document?.plainText;
  }

  Future<LyricsDocument?> loadLyricsDocumentForCurrent({
    String? explicitPath,
    bool searchOnline = true,
  }) async {
    final music = currentMusic;
    if (music == null || kIsWeb) return null;
    final expectedLyricsKey = _lyricsOwnerKey(music);

    final candidates = <String>[
      if (explicitPath != null) explicitPath,
      await _manualLyricsPathForMusic(music),
      await _manualPlainLyricsPathForMusic(music),
      ..._lyricsSidecarCandidates(music.filePath),
    ];

    for (final candidate in candidates) {
      final file = File(candidate);
      if (!await file.exists()) continue;
      try {
        final raw = await file.readAsString();
        final document = LyricsDocument.parse(raw, source: candidate);
        if (document.lines.isNotEmpty &&
            await _lyricsCandidateMatchesMusic(candidate, music)) {
          if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
          return document;
        }
      } catch (e) {
        debugPrint('Error reading lyrics: $e');
      }
    }

    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    if (!searchOnline) return null;
    final fetched = await _tryFetchLyricsOnline(music);
    if (fetched == null) return null;
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    final saved = await _saveFetchedLyricsForMusic(
      music,
      fetched,
      requireNameMatch: true,
    );
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    return saved;
  }

  Future<LyricsDocument?> saveLyricsForCurrent(String rawLyrics) async {
    final music = currentMusic;
    if (music == null || kIsWeb) return null;
    final expectedLyricsKey = _lyricsOwnerKey(music);
    final path = await _manualLyricsPathForMusic(music);
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(rawLyrics);
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    return LyricsDocument.parse(rawLyrics, source: path);
  }

  Future<LyricsDocument?> searchLyricsForCurrentOnline() async {
    final music = currentMusic;
    if (music == null || kIsWeb) return null;
    final expectedLyricsKey = _lyricsOwnerKey(music);
    final fetched = await _tryFetchLyricsOnline(music);
    if (fetched == null) return null;
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    final saved = await _saveFetchedLyricsForMusic(
      music,
      fetched,
      requireNameMatch: true,
    );
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    return saved;
  }

  Future<LyricsDocument?> searchLyricsForCurrentWithCustomParameters({
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
  }) async {
    final music = currentMusic;
    if (music == null || kIsWeb) return null;
    final queries = _manualLyricsQueries(
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
    );
    if (queries.isEmpty) return null;

    final expectedLyricsKey = _lyricsOwnerKey(music);
    final fetched = await _fetchLyricsOnlineForQueries(queries);
    if (fetched == null) return null;
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    final saved = await _saveFetchedLyricsForMusic(
      music,
      fetched,
      requireNameMatch: true,
    );
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    return saved;
  }

  Future<List<LrclibLyrics>> searchLyricsResultsForCurrent({
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
  }) async {
    if (currentMusic == null || kIsWeb) return const [];
    final queries = _manualLyricsQueries(
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
    );
    if (queries.isEmpty) return const [];
    return _fetchLyricsResultsOnlineForQueries(queries);
  }

  Future<LyricsDocument?> saveLyricsResultForCurrent(
    LrclibLyrics lyrics,
  ) async {
    final music = currentMusic;
    if (music == null || kIsWeb) return null;
    final expectedLyricsKey = _lyricsOwnerKey(music);
    final saved = await _saveFetchedLyricsForMusic(
      music,
      lyrics,
      requireNameMatch: false,
    );
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    return saved;
  }

  Future<String> editableLyricsForCurrent() async {
    final document = await loadLyricsDocumentForCurrent(searchOnline: false);
    return document?.rawText ?? '';
  }

  Future<String> _manualLyricsPathForMusic(Music music) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = '${_safeLyricsFileToken(music)}.lrc';
    return p.join(dir.path, 'lyrics', fileName);
  }

  Future<String> _manualPlainLyricsPathForMusic(Music music) async {
    final dir = await getApplicationDocumentsDirectory();
    final fileName = '${_safeLyricsFileToken(music)}.txt';
    return p.join(dir.path, 'lyrics', fileName);
  }

  String _lyricsOwnerKey(Music music) {
    return '${music.id}\n${p.normalize(music.filePath)}';
  }

  bool _isCurrentLyricsOwner(String expectedLyricsKey) {
    final music = currentMusic;
    return music != null && _lyricsOwnerKey(music) == expectedLyricsKey;
  }

  String _safeLyricsFileToken(Music music) {
    final pathHash = sha1.convert(utf8.encode(p.normalize(music.filePath)));
    return '${_safeFileToken(music.id)}_${pathHash.toString().substring(0, 16)}';
  }

  String _safeFileToken(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'track' : cleaned;
  }

  Future<LrclibLyrics?> _tryFetchLyricsOnline(Music music) async {
    final queries = _lyricsQueriesForMusic(music);
    if (queries.isEmpty) {
      return null;
    }

    return _fetchLyricsOnlineForQueries(queries);
  }

  Future<LrclibLyrics?> _fetchLyricsOnlineForQueries(
    List<_LyricsQuery> queries,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      for (final query in queries) {
        final exact = await _fetchLrclibExact(client, query);
        if (exact != null &&
            exact.hasLyrics &&
            _lyricsResultMatchesQuery(exact, query)) {
          return exact;
        }
      }

      final searched = <_ScoredLrclibLyrics>[];
      final seen = <int>{};
      for (final query in queries) {
        for (final result in await _searchLrclib(client, query)) {
          final id = result.id;
          if (id != null && !seen.add(id)) continue;
          if (!_lyricsResultMatchesQuery(result, query)) continue;
          searched.add(_ScoredLrclibLyrics(
            lyrics: result,
            score: _scoreLrclibResult(result, query),
          ));
        }
      }
      if (searched.isEmpty) return null;

      searched.sort((a, b) => b.score.compareTo(a.score));
      searched.sort((a, b) {
        final syncCompare = (b.lyrics.hasSyncedLyrics ? 1 : 0) -
            (a.lyrics.hasSyncedLyrics ? 1 : 0);
        if (syncCompare != 0) return syncCompare;
        return b.score.compareTo(a.score);
      });
      for (final scored in searched) {
        final result = scored.lyrics;
        if (result.hasLyrics) return result;
        final id = result.id;
        if (id == null) continue;
        final full = await _fetchLrclibById(client, id);
        if (full != null &&
            full.hasLyrics &&
            queries.any((query) => _lyricsResultMatchesQuery(full, query))) {
          return full;
        }
      }
    } catch (e) {
      debugPrint('Auto lyrics search failed: $e');
    } finally {
      client?.close(force: true);
    }
    return null;
  }

  Future<List<LrclibLyrics>> _fetchLyricsResultsOnlineForQueries(
    List<_LyricsQuery> queries,
  ) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final scored = <_ScoredLrclibLyrics>[];
      final seen = <int>{};

      for (final query in queries) {
        final exact = await _fetchLrclibExact(client, query);
        if (exact != null &&
            exact.hasLyrics &&
            _lyricsResultMatchesQuery(exact, query)) {
          final id = exact.id;
          if (id == null || seen.add(id)) {
            scored.add(_ScoredLrclibLyrics(
              lyrics: exact,
              score: _scoreLrclibResult(exact, query) + 10,
            ));
          }
        }

        for (final result in await _searchLrclib(client, query)) {
          final id = result.id;
          if (id != null && !seen.add(id)) continue;
          if (!_lyricsResultMatchesQuery(result, query)) continue;
          scored.add(_ScoredLrclibLyrics(
            lyrics: result,
            score: _scoreLrclibResult(result, query),
          ));
        }
      }

      scored.sort((a, b) {
        final syncCompare = (b.lyrics.hasSyncedLyrics ? 1 : 0) -
            (a.lyrics.hasSyncedLyrics ? 1 : 0);
        if (syncCompare != 0) return syncCompare;
        return b.score.compareTo(a.score);
      });
      return scored.map((item) => item.lyrics).toList();
    } catch (e) {
      debugPrint('Lyrics result search failed: $e');
      return const [];
    } finally {
      client?.close(force: true);
    }
  }

  List<_LyricsQuery> _lyricsQueriesForMusic(Music music) {
    final title = _cleanLyricsSearchText(_metadataTitle(music));
    final artist = _cleanLyricsSearchText(_metadataArtist(music));
    final album = music.album.trim();
    final duration = music.duration ?? _duration;
    final durationSeconds = duration > Duration.zero
        ? duration.inMilliseconds ~/ Duration.millisecondsPerSecond
        : null;
    final albumName = album.isEmpty || album == 'Unknown Album'
        ? null
        : _cleanLyricsSearchText(album);
    final queries = <_LyricsQuery>[];

    void addQuery(String trackName, String artistName, {String? album}) {
      final cleanTrack = _cleanLyricsSearchText(trackName);
      final cleanArtist = _cleanLyricsSearchText(artistName);
      if (cleanTrack.isEmpty ||
          cleanArtist.isEmpty ||
          cleanArtist == 'Unknown Artist') {
        return;
      }
      final key =
          '${_normalizeLyricsToken(cleanArtist)}|${_normalizeLyricsToken(cleanTrack)}';
      if (queries.any((query) =>
          '${_normalizeLyricsToken(query.artistName)}|${_normalizeLyricsToken(query.trackName)}' ==
          key)) {
        return;
      }
      queries.add(_LyricsQuery(
        trackName: cleanTrack,
        artistName: cleanArtist,
        albumName: album,
        durationSeconds: durationSeconds,
      ));
    }

    if (title.isNotEmpty && artist.isNotEmpty) {
      addQuery(title, artist, album: albumName);
    }

    return queries;
  }

  List<_LyricsQuery> _manualLyricsQueries({
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
  }) {
    final cleanTrack = _cleanLyricsSearchText(title);
    final cleanArtist = _cleanLyricsSearchText(artist);
    final cleanAlbum = album == null || album.trim().isEmpty
        ? null
        : _cleanLyricsSearchText(album);
    if (cleanTrack.isEmpty && cleanArtist.isEmpty) return const [];

    final queries = <_LyricsQuery>[];

    void addQuery({
      required String trackName,
      required String artistName,
      String? albumName,
    }) {
      if (trackName.isEmpty && artistName.isEmpty) return;
      final key =
          '${_normalizeLyricsToken(artistName)}|${_normalizeLyricsToken(trackName)}|${_normalizeLyricsToken(albumName ?? '')}';
      if (queries.any((query) =>
          '${_normalizeLyricsToken(query.artistName)}|${_normalizeLyricsToken(query.trackName)}|${_normalizeLyricsToken(query.albumName ?? '')}' ==
          key)) {
        return;
      }
      queries.add(_LyricsQuery(
        trackName: trackName,
        artistName: artistName,
        albumName: albumName == null || albumName.isEmpty ? null : albumName,
        durationSeconds: durationSeconds,
      ));
    }

    addQuery(
      trackName: cleanTrack,
      artistName: cleanArtist,
      albumName: cleanAlbum,
    );

    if (cleanTrack.isNotEmpty && cleanArtist.isEmpty) {
      addQuery(trackName: cleanTrack, artistName: '', albumName: cleanAlbum);
    }

    if (cleanArtist.isNotEmpty && cleanTrack.isEmpty) {
      addQuery(trackName: '', artistName: cleanArtist, albumName: cleanAlbum);
    }

    return queries;
  }

  Future<LrclibLyrics?> _fetchLrclibExact(
    HttpClient client,
    _LyricsQuery query,
  ) async {
    if (query.trackName.isEmpty || query.artistName.isEmpty) return null;
    final params = <String, String>{
      'track_name': query.trackName,
      'artist_name': query.artistName,
      if (query.albumName != null) 'album_name': query.albumName!,
      if (query.durationSeconds != null)
        'duration': query.durationSeconds!.toString(),
    };
    final decoded = await _getLrclibJson(client, '/api/get', params);
    return decoded is Map
        ? LrclibLyrics.fromJson(Map<String, dynamic>.from(decoded))
        : null;
  }

  Future<LrclibLyrics?> _fetchLrclibById(HttpClient client, int id) async {
    final decoded = await _getLrclibJson(client, '/api/get/$id', const {});
    return decoded is Map
        ? LrclibLyrics.fromJson(Map<String, dynamic>.from(decoded))
        : null;
  }

  Future<List<LrclibLyrics>> _searchLrclib(
    HttpClient client,
    _LyricsQuery query,
  ) async {
    final searches = <Map<String, String>>[
      if (query.trackName.isNotEmpty && query.artistName.isNotEmpty)
        <String, String>{
          'track_name': query.trackName,
          'artist_name': query.artistName,
          if (query.albumName != null) 'album_name': query.albumName!,
        },
      <String, String>{
        'q': [
          query.artistName,
          query.trackName,
          if (query.albumName != null) query.albumName!,
        ].where((part) => part.trim().isNotEmpty).join(' '),
      },
    ]
        .where((params) => params.values.any((value) => value.isNotEmpty))
        .toList();

    final results = <LrclibLyrics>[];
    final seen = <int>{};
    for (final params in searches) {
      final decoded = await _getLrclibJson(client, '/api/search', params);
      if (decoded is! List) continue;
      for (final item in decoded.whereType<Map>()) {
        final result = LrclibLyrics.fromJson(Map<String, dynamic>.from(item));
        final id = result.id;
        if (id != null && !seen.add(id)) continue;
        results.add(result);
      }
    }
    return results;
  }

  Future<dynamic> _getLrclibJson(
    HttpClient client,
    String path,
    Map<String, String> params,
  ) async {
    final uri = Uri.https('lrclib.net', path, params.isEmpty ? null : params);
    final request =
        await client.getUrl(uri).timeout(const Duration(seconds: 6));
    request.headers.set(HttpHeaders.userAgentHeader, 'PlayerVf/1.0');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode == HttpStatus.notFound) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'LRCLIB request failed with ${response.statusCode}',
        uri: uri,
      );
    }
    final raw = await utf8.decoder.bind(response).join();
    if (raw.trim().isEmpty) return null;
    return jsonDecode(raw);
  }

  int _scoreLrclibResult(LrclibLyrics lyrics, _LyricsQuery query) {
    var score = 0;
    if (_lyricsResultHasRequestedName(lyrics, query)) score += 100;
    if (query.artistName.isNotEmpty &&
        _sameLyricsToken(lyrics.artistName, query.artistName)) {
      score += 12;
    }
    if (query.albumName != null &&
        _sameLyricsToken(lyrics.albumName, query.albumName!)) {
      score += 3;
    }
    if (query.durationSeconds != null && lyrics.durationSeconds != null) {
      final delta = (lyrics.durationSeconds! - query.durationSeconds!).abs();
      if (delta <= 2) {
        score += 4;
      } else if (delta <= 8) {
        score += 2;
      }
    }
    if (lyrics.syncedLyrics != null) score += 2;
    if (lyrics.plainLyrics != null) score += 1;
    return score;
  }

  bool _lyricsResultMatchesQuery(LrclibLyrics lyrics, _LyricsQuery query) {
    final hasRequestedName = _lyricsResultHasRequestedName(lyrics, query);
    final hasRequestedArtist = query.artistName.isNotEmpty &&
        _sameLyricsToken(lyrics.artistName, query.artistName);
    if (query.trackName.isNotEmpty && query.artistName.isNotEmpty) {
      return hasRequestedName && hasRequestedArtist;
    }
    if (query.trackName.isNotEmpty) return hasRequestedName;
    if (query.artistName.isNotEmpty) return hasRequestedArtist;
    return false;
  }

  bool _lyricsResultHasRequestedName(LrclibLyrics lyrics, _LyricsQuery query) {
    if (query.trackName.isEmpty) return false;
    return _sameLyricsToken(lyrics.trackName, query.trackName);
  }

  bool _sameLyricsToken(String? left, String right) {
    if (left == null) return false;
    return _normalizeLyricsToken(left) == _normalizeLyricsToken(right);
  }

  String _normalizeLyricsToken(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String _cleanLyricsSearchText(String value) {
    return value
        .replaceAll(
            RegExp(r'\.(mp3|m4a|flac|wav|ogg|aac|wma)$', caseSensitive: false),
            '')
        .replaceAll(
            RegExp(r'\b(official|audio|video|lyrics?|lyric video)\b',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<LyricsDocument?> _saveFetchedLyricsForMusic(
    Music music,
    LrclibLyrics lyrics, {
    required bool requireNameMatch,
  }) async {
    if (kIsWeb) return null;
    if (requireNameMatch && !_lyricsResultMatchesMusicName(lyrics, music)) {
      return null;
    }

    final synced = lyrics.syncedLyrics?.trim();
    final parsedSynced = synced == null || synced.isEmpty
        ? null
        : LyricsDocument.parse(synced, source: 'lrclib');
    final plain = (lyrics.plainLyrics?.trim().isNotEmpty == true
            ? lyrics.plainLyrics!.trim()
            : parsedSynced?.plainText.trim())
        ?.trim();
    String? preferredPath;
    String? preferredRaw;

    if (synced != null && synced.isNotEmpty) {
      final path = await _manualLyricsPathForMusic(music);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(synced);
      preferredPath = path;
      preferredRaw = synced;
    }

    if (plain != null && plain.isNotEmpty) {
      final path = await _manualPlainLyricsPathForMusic(music);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(plain);
      preferredPath ??= path;
      preferredRaw ??= plain;
    }

    if (preferredPath == null || preferredRaw == null) return null;
    return LyricsDocument.parse(preferredRaw, source: preferredPath);
  }

  bool _lyricsResultMatchesMusicName(LrclibLyrics lyrics, Music music) {
    final currentName = _cleanLyricsSearchText(_metadataTitle(music));
    if (currentName.isEmpty) return false;
    return _sameLyricsToken(lyrics.trackName, currentName);
  }

  List<String> _lyricsSidecarCandidates(String mediaPath) {
    final dir = p.dirname(mediaPath);
    final name = p.basenameWithoutExtension(mediaPath);
    return [
      p.join(dir, '$name.lrc'),
      p.join(dir, '$name.txt'),
      p.join(dir, '$name.lyrics'),
    ];
  }

  Future<bool> _lyricsCandidateMatchesMusic(
      String candidate, Music music) async {
    final basename = p.basenameWithoutExtension(candidate);
    final safeId = _safeLyricsFileToken(music);
    final appDir = await getApplicationDocumentsDirectory();
    final appLyricsDir = p.normalize(p.join(appDir.path, 'lyrics'));
    final candidateDir = p.normalize(p.dirname(candidate));
    if (p.equals(candidateDir, appLyricsDir) && basename != safeId) {
      return false;
    }
    return true;
  }

  Future<void> _setPlayerVolume(Player player, double value) async {
    final nextVolume = _effectiveBackendVolume(value);
    await player.setVolume(nextVolume);
  }

  double _effectiveBackendVolume(double value) {
    return (value * _effectsVolumeFactor).clamp(0.0, 100.0).toDouble();
  }

  bool _shouldUseNativeWindowsAudio(Music track) {
    // Keep Windows playback on media_kit. just_audio_windows currently emits
    // non-platform-thread channel messages on this app and can disconnect the
    // debugger/device during normal play/pause/load operations.
    if (!kIsWeb && Platform.isWindows) return false;
    if (!_windowsNativeAudioAvailable ||
        kIsWeb ||
        !Platform.isWindows ||
        _isVideoTrack(track)) {
      return false;
    }
    final path = track.filePath.trim().toLowerCase();
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:')) {
      return false;
    }
    final extension = p.extension(path);
    return const {'.mp3', '.wav', '.m4a', '.aac'}.contains(extension);
  }

  Duration _sanitizeSongGap(Duration duration) {
    return Duration(
      milliseconds: duration.inMilliseconds.clamp(0, 5000),
    );
  }

  Future<void> setSongGapDuration(Duration duration) async {
    _songGapDuration = _sanitizeSongGap(duration);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      SettingsModel.songGapMsKey,
      _songGapDuration.inMilliseconds,
    );
    notifyListeners();
  }

  Future<void> _waitForSongGapIfNeeded(int generation, bool shouldGap) async {
    final gap = _songGapDuration;
    if (!shouldGap || gap <= Duration.zero) return;
    await Future<void>.delayed(gap);
    if (generation != _audioTransitionGeneration) return;
  }

  Future<void> _setPlayerVolumeInternal(Player player, double value) async {
    _internalVolumeChangeDepth++;
    try {
      await _setPlayerVolume(player, value);
    } finally {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 80), () {
        _internalVolumeChangeDepth = max(0, _internalVolumeChangeDepth - 1);
      }));
    }
  }

  Future<void> _setOutputVolume(double value) async {
    if (_usingNativeWindowsAudio) {
      await _audioHandler.setVolumeFromService(
        _effectiveBackendVolume(value) / 100.0,
      );
      return;
    }
    await _setPlayerVolume(_mediaPlayer, value);
  }

  Future<void> _setBackendVolume(double value, {bool internal = false}) async {
    if (!internal) {
      await _setOutputVolume(value);
      return;
    }

    _isInternalVolumeChange = true;
    try {
      await _setOutputVolume(value);
    } finally {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 60), () {
        _isInternalVolumeChange = false;
      }));
    }
  }

  Future<void> _fadeBackendVolume(
    double from,
    double to,
    Duration duration,
    int generation, {
    Player? player,
  }) async {
    if (_volume <= 0) return;

    final targetPlayer = player ?? _mediaPlayer;
    final steps = max(6, duration.inMilliseconds ~/ 14);
    final intervalMs = max(1, duration.inMilliseconds ~/ steps);
    for (var i = 0; i <= steps; i++) {
      if (generation != _audioTransitionGeneration) return;
      final t = i / steps;
      final eased = t * t * (3 - (2 * t));
      await _setPlayerVolumeInternal(
          targetPlayer, from + ((to - from) * eased));
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
    if (generation == _audioTransitionGeneration) {
      await _setPlayerVolumeInternal(targetPlayer, to);
    }
  }

  Future<void> _smoothOpenAndPlay(Music track, Duration startPosition) async {
    final generation = ++_audioTransitionGeneration;
    final targetVolume = _volume.clamp(0.0, 100.0);
    final currentPlayer = _mediaPlayer;
    final useNativeWindowsAudio = _shouldUseNativeWindowsAudio(track);
    final isSwitchingTracks = _openedMusicId != null &&
        _openedMusicId != track.id &&
        startPosition <= Duration.zero;
    final shouldGapBetweenTracks =
        isSwitchingTracks && _songGapDuration > Duration.zero;
    final canCrossfade = _isPlaying &&
        !shouldGapBetweenTracks &&
        !_usingNativeWindowsAudio &&
        !useNativeWindowsAudio &&
        !_hasVideoTrack &&
        !_isVideoTrack(track);
    _suppressPositionUpdatesForTrackChange = true;
    _setDurationForOpeningTrack(track);
    _position = startPosition;
    _positionNotifier.value = startPosition;

    if (!canCrossfade) {
      try {
        if (_isPlaying && targetVolume > 0) {
          await _fadeBackendVolume(
            targetVolume,
            0,
            _singlePlayerFadeOutDuration,
            generation,
            player: currentPlayer,
          );
        }

        if (_isPlaying) await _pauseCurrentBackend();
        await _waitForSongGapIfNeeded(generation, shouldGapBetweenTracks);
        if (generation != _audioTransitionGeneration) return;
        await _openTrackMedia(track);

        if (startPosition > Duration.zero) {
          await _seekCurrentBackend(startPosition);
          _position = startPosition;
          _positionNotifier.value = startPosition;
        }

        if (_shouldResumeCurrentTrack) {
          await _applyResumePositionIfNeeded(track.id);
        }

        _suppressPositionUpdatesForTrackChange = false;
        if (targetVolume > 0) {
          await _setBackendVolume(0, internal: true);
        }
        await _playCurrentBackend();
        if (targetVolume > 0) {
          await _fadeBackendVolume(
            0,
            targetVolume,
            _singlePlayerFadeInDuration,
            generation,
          );
        }
        await _setBackendVolume(targetVolume, internal: true);
      } finally {
        if (generation == _audioTransitionGeneration) {
          _suppressPositionUpdatesForTrackChange = false;
        }
      }
      return;
    }

    final incomingPlayer = Player();
    _retiringPlayer = currentPlayer;

    try {
      await _preparePlayerForTrack(
        incomingPlayer,
        track,
        volume: targetVolume > 0 ? 0 : targetVolume,
      );

      _position = startPosition;
      _positionNotifier.value = startPosition;
      if (startPosition > Duration.zero) {
        await incomingPlayer.seek(startPosition);
      }
      if (_shouldResumeCurrentTrack) {
        await _applyResumePositionOnPlayerIfNeeded(incomingPlayer, track.id);
      }

      await incomingPlayer.play();
      _syncExternalPlaybackState(playing: true, position: _position);

      if (targetVolume > 0) {
        await Future.wait([
          _fadeBackendVolume(
            targetVolume,
            0,
            _manualCrossfadeDuration,
            generation,
            player: currentPlayer,
          ),
          _fadeBackendVolume(
            0,
            targetVolume,
            _manualCrossfadeDuration,
            generation,
            player: incomingPlayer,
          ),
        ]);
      }

      if (generation == _audioTransitionGeneration) {
        _bindPlayer(incomingPlayer);
        _suppressPositionUpdatesForTrackChange = false;
        await _setBackendVolume(targetVolume, internal: true);
        await currentPlayer.pause();
        unawaited(currentPlayer.dispose());
      } else {
        unawaited(incomingPlayer.dispose());
      }
    } catch (e) {
      unawaited(incomingPlayer.dispose());
      await _setPlayerVolume(currentPlayer, targetVolume);
      rethrow;
    } finally {
      if (_retiringPlayer == currentPlayer) {
        _retiringPlayer = null;
      }
      if (generation == _audioTransitionGeneration) {
        _suppressPositionUpdatesForTrackChange = false;
      }
    }
  }

  void _setDurationForOpeningTrack(Music track) {
    _duration = track.duration ?? Duration.zero;
    _durationNotifier.value = _duration;
  }

  Future<void> _smoothPlayCurrentBackend() async {
    if (_usingNativeWindowsAudio) {
      await _playCurrentBackend();
      return;
    }
    final targetVolume = _volume.clamp(0.0, 100.0);
    final generation = ++_audioTransitionGeneration;

    if (targetVolume > 0) {
      await _setBackendVolume(0, internal: true);
    }

    await _playCurrentBackend();

    if (targetVolume > 0) {
      await _fadeBackendVolume(
        0,
        targetVolume,
        _playFadeInDuration,
        generation,
      );
    }

    if (generation == _audioTransitionGeneration) {
      await _setBackendVolume(targetVolume, internal: true);
    }
  }

  Future<void> _smoothPauseCurrentBackend() async {
    if (_usingNativeWindowsAudio) {
      await _pauseCurrentBackend();
      return;
    }
    final targetVolume = _volume.clamp(0.0, 100.0);
    final generation = ++_audioTransitionGeneration;

    _setLocalPlayingState(false);
    if (targetVolume > 0) {
      await _fadeBackendVolume(
        targetVolume,
        0,
        _pauseFadeOutDuration,
        generation,
      );
    }

    if (generation != _audioTransitionGeneration) return;
    await _pauseCurrentBackend();
    if (targetVolume > 0) {
      await _setBackendVolume(targetVolume, internal: true);
    }
  }

  void _setLocalPlayingState(bool state) {
    if (_isPlaying == state && _playingNotifier.value == state) {
      _syncExternalPlaybackState(playing: state);
      return;
    }
    _isPlaying = state;
    _playingNotifier.value = state;
    _syncExternalPlaybackState(playing: state);
    _savePlaybackDebounced();
    notifyListeners();
  }

  Future<void> _preparePlayerForTrack(
    Player player,
    Music track, {
    required double volume,
  }) async {
    _completedTrackId = null;
    _hasVideoTrack = _isVideoTrack(track);
    await _ensureVideoControllerForCurrentTrack();
    await _audioHandler.updateNowPlaying(
      track,
      playing: _isPlaying,
      position: _position,
      duration: track.duration,
    );
    await _setPlayerVolume(player, volume);
    await _applyDecoderSettings(player);
    _lastNativeAudioFilterKey = null;
    await player.open(
      Media(
        track.filePath,
        extras: {
          'title': _metadataTitle(track),
          'artist': _metadataArtist(track),
          'album': track.album,
          'artwork': track.coverPath,
        },
      ),
      play: false,
    );
    await _applySidecarSubtitleIfAvailable(player, track.filePath);
    await _applyAudioEffects(player);
    _audioHandler.setExternalPlaybackState(
      playing: _isPlaying,
      position: _position,
      duration: _duration,
    );
  }

  Future<void> _applyResumePositionOnPlayerIfNeeded(
      Player player, String trackId) async {
    if (!_shouldResumeCurrentTrack ||
        _resumeTrackId != trackId ||
        _resumePosition <= Duration.zero) {
      return;
    }

    final currentDelta = (_position - _resumePosition).inMilliseconds.abs();
    if (currentDelta < 800) {
      return;
    }

    await player.seek(_resumePosition);
    _position = _resumePosition;
    _positionNotifier.value = _resumePosition;
  }

  Future<void> _openTrackMedia(Music track) async {
    _hasVideoTrack = _isVideoTrack(track);
    _completedTrackId = null;
    _lastNativeAudioFilterKey = null;
    await _ensureVideoControllerForCurrentTrack();
    final useNativeWindowsAudio = _shouldUseNativeWindowsAudio(track);
    _usingNativeWindowsAudio = useNativeWindowsAudio;
    if (useNativeWindowsAudio) {
      try {
        await _mediaPlayer.pause();
        await _audioHandler.openTrack(track);
        await _audioHandler.setVolumeFromService(
          _effectiveBackendVolume(_volume) / 100.0,
        );
        await _applyNativeWindowsAudioEffects();
        _audioHandler.setExternalPlaybackState(
          playing: false,
          position: _position,
          duration: _duration,
        );
        return;
      } catch (e) {
        debugPrint(
            'Native Windows audio failed, falling back to media_kit: $e');
        _usingNativeWindowsAudio = false;
        _windowsNativeAudioAvailable = false;
        await _audioHandler.stop();
      }
    }

    await _audioHandler.updateNowPlaying(
      track,
      playing: false,
      position: _position,
      duration: track.duration,
    );
    await _applyDecoderSettings(_mediaPlayer);
    await _mediaPlayer.open(
      Media(
        track.filePath,
        extras: {
          'title': _metadataTitle(track),
          'artist': _metadataArtist(track),
          'album': track.album,
          'artwork': track.coverPath,
        },
      ),
      play: false,
    );
    await _applySidecarSubtitleIfAvailable(_mediaPlayer, track.filePath);
    await _setOutputVolume(_volume);
    await _scheduleUpdateNow();
    _audioHandler.setExternalPlaybackState(
      playing: false,
      position: _position,
      duration: _duration,
    );
  }

  Future<void> _scheduleUpdateNow() async {
    _effectsUpdateTimer?.cancel();
    _hasPendingUpdate = false;
    await _applyScheduledEffects();
  }

  Future<void> _clearNowPlaying() async {
    try {
      _usingNativeWindowsAudio = false;
      await _audioHandler.stop();
      await _mediaPlayer.stop();
    } catch (_) {
      // Platform now-playing integration is best effort.
    }
  }

  Future<void> _playCurrentBackend() async {
    if (_usingNativeWindowsAudio) {
      await _audioHandler.playFromService();
      _setLocalPlayingState(true);
      return;
    }
    await _mediaPlayer.play();
    unawaited(_scheduleUpdateNow());
    _setLocalPlayingState(true);
  }

  Future<void> _pauseCurrentBackend() async {
    if (_usingNativeWindowsAudio) {
      await _audioHandler.pauseFromService();
      _setLocalPlayingState(false);
      return;
    }
    await _mediaPlayer.pause();
    _setLocalPlayingState(false);
  }

  Future<void> _seekCurrentBackend(Duration position) async {
    if (_usingNativeWindowsAudio) {
      await _audioHandler.seekFromService(position);
      return;
    }
    await _mediaPlayer.seek(position);
    _syncExternalPlaybackState(position: position);
  }

  void _syncExternalPlaybackState({bool? playing, Duration? position}) {
    _audioHandler.setExternalPlaybackState(
      playing: playing ?? _isPlaying,
      position: position ?? _position,
      duration: _duration,
    );
  }

  Future<void> play() async {
    if (_streamingMusic != null) {
      await _playStreamingCurrent();
      return;
    }
    if (_musicList.isEmpty) return;
    _ensureQueueInitialized();
    try {
      final track = _musicList[_currentIndex];
      final trackId = track.id;
      _usingNativeWindowsAudio = _shouldUseNativeWindowsAudio(track);

      if (_openedMusicId == trackId) {
        if (_shouldResumeCurrentTrack) {
          await _applyResumePositionIfNeeded(trackId);
        }
        await _smoothPlayCurrentBackend();
        _musicList[_currentIndex].lastPlayed = DateTime.now();
        _shouldResumeCurrentTrack = false;
        _saveStats();
        _savePlaybackDebounced();
        notifyListeners();
        return;
      }

      final startPosition =
          (_shouldResumeCurrentTrack && _resumeTrackId == trackId)
              ? _resumePosition
              : Duration.zero;
      _hasVideoTrack = false; // Reset before opening new media
      await _smoothOpenAndPlay(track, startPosition);
      _openedMusicId = trackId;

      track.playCount++;
      track.lastPlayed = DateTime.now();
      _resumeTrackId = trackId;
      _resumePosition = _position;
      _shouldResumeCurrentTrack = false;
      _scheduleUpdate();
      _saveStats();
      _savePlaybackDebounced();
      notifyListeners();
    } catch (e) {
      debugPrint('Play Error: $e');
    }
  }

  Future<void> _playStreamingCurrent() async {
    final track = _streamingMusic;
    if (track == null) return;
    _usingNativeWindowsAudio = false;

    try {
      final trackId = track.id;
      if (_openedMusicId == trackId) {
        await _playCurrentBackend();
        notifyListeners();
        return;
      }

      _hasVideoTrack = false;
      _position = Duration.zero;
      _positionNotifier.value = Duration.zero;
      _duration = track.duration ?? Duration.zero;
      _durationNotifier.value = _duration;
      await _smoothOpenAndPlay(track, Duration.zero);
      _openedMusicId = trackId;

      _resumeTrackId = trackId;
      _resumePosition = Duration.zero;
      _shouldResumeCurrentTrack = false;
      _scheduleUpdate();
      notifyListeners();
    } catch (e) {
      debugPrint('Stream Play Error: $e');
    }
  }

  void togglePlayPause() {
    unawaited(_runPlaybackCommand(
      _togglePlayPauseInternal,
      dropIfActive: true,
    ));
  }

  Future<void> _runPlaybackCommand(
    Future<void> Function() action, {
    bool dropIfActive = false,
  }) async {
    if (_isPlaybackCommandActive) {
      if (dropIfActive) return;
      _pendingPlaybackCommand = action;
      return;
    }
    _isPlaybackCommandActive = true;
    try {
      do {
        _pendingPlaybackCommand = null;
        await action();
        action = _pendingPlaybackCommand ?? action;
      } while (_pendingPlaybackCommand != null);
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 35));
      _isPlaybackCommandActive = false;
    }
  }

  Future<void> _togglePlayPauseInternal() async {
    if (!_isPlaying && currentMusic != null) {
      if (_openedMusicId != currentMusic!.id) {
        await play();
        return;
      }
      if (_shouldResumeCurrentTrack) {
        await _applyResumePositionIfNeeded(currentMusic!.id);
      }
      _shouldResumeCurrentTrack = false;
      await _smoothPlayCurrentBackend();
    } else if (_isPlaying && currentMusic != null) {
      _resumeTrackId = currentMusic!.id;
      _resumePosition = _position;
      _shouldResumeCurrentTrack = true;
      await _smoothPauseCurrentBackend();
    } else {
      if (_isPlaying) {
        await _smoothPauseCurrentBackend();
      } else {
        await _smoothPlayCurrentBackend();
      }
    }
  }

  void seekTo(Duration position) {
    unawaited(_seekCurrentBackend(position));
    _position = position;
    _positionNotifier.value = position;
    _resumeTrackId = currentMusic?.id;
    _resumePosition = position;
    _shouldResumeCurrentTrack = position > Duration.zero;
    if (_streamingMusic == null) {
      _savePlaybackDebounced();
    }
    notifyListeners();
  }

  void setVolume(double volume) {
    final previous = _volume;
    _volume = volume.clamp(0.0, 100.0);
    _volumeNotifier.value = _volume;
    unawaited(_smoothSetUserVolume(previous, _volume));
  }

  Future<void> _smoothSetUserVolume(double from, double to) async {
    final generation = ++_volumeChangeGeneration;
    if ((from - to).abs() < 0.5) {
      await _setBackendVolume(to);
      return;
    }

    const duration = Duration(milliseconds: 140);
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      if (generation != _volumeChangeGeneration) return;
      final t = i / steps;
      final eased = t * t * (3 - (2 * t));
      await _setBackendVolume(from + ((to - from) * eased));
      await Future<void>.delayed(
        Duration(milliseconds: duration.inMilliseconds ~/ steps),
      );
    }
    if (generation == _volumeChangeGeneration) {
      await _setBackendVolume(to);
    }
  }

  void next() {
    unawaited(_runPlaybackCommand(_nextInternal));
  }

  Future<void> _nextInternal() async {
    if (_streamingMusic != null) return;
    _clearResumeState(keepOpenedTrack: false);
    if (_moveInQueue(1)) {
      await play();
    }
  }

  void previous() {
    unawaited(_runPlaybackCommand(_previousInternal));
  }

  void previousTrack() {
    unawaited(
        _runPlaybackCommand(() => _previousInternal(forcePrevious: true)));
  }

  void restartCurrentTrack() {
    seekTo(Duration.zero);
  }

  void previousOrRestartShortcut() {
    unawaited(_runPlaybackCommand(_previousOrRestartShortcutInternal));
  }

  Future<void> _previousOrRestartShortcutInternal() async {
    if (_streamingMusic != null) {
      seekTo(Duration.zero);
      return;
    }
    if (_musicList.isEmpty) return;
    if (_position >= const Duration(seconds: 3)) {
      seekTo(Duration.zero);
      return;
    }
    _clearResumeState(keepOpenedTrack: false);
    if (_moveInQueue(-1)) {
      await play();
    } else {
      seekTo(Duration.zero);
    }
  }

  Future<void> _previousInternal({bool forcePrevious = false}) async {
    if (_streamingMusic != null) {
      seekTo(Duration.zero);
      return;
    }
    if (_musicList.isEmpty) return;
    if (!forcePrevious && _position >= const Duration(seconds: 3)) {
      seekTo(Duration.zero);
      return;
    }
    _clearResumeState(keepOpenedTrack: false);
    if (_moveInQueue(-1)) {
      await play();
    } else {
      seekTo(Duration.zero);
    }
  }

  void toggleShuffle() {
    if (_streamingMusic != null) return;
    _isShuffle = !_isShuffle;
    _rebuildShuffledQueue();
    _savePlaybackDebounced();
    notifyListeners();
  }

  void toggleRepeatMode() {
    if (_isRepeatAll && !_isRepeatOne) {
      _isRepeatAll = false;
      _isRepeatOne = true;
    } else if (!_isRepeatAll && _isRepeatOne) {
      _isRepeatOne = false;
    } else {
      _isRepeatAll = true;
      _isRepeatOne = false;
    }
    _savePlaybackDebounced();
    notifyListeners();
  }

  Future<void> loadSystemMusic(
      {List<String>? customPaths, bool clearExisting = true}) async {
    if (_isLoadingSystemMusic) return;

    final hasPermission = await MusicScannerService.checkPermissions();
    if (!hasPermission) return;

    _isLoadingSystemMusic = true;
    if (customPaths != null) {
      if (clearExisting || _lastUsedPaths == null) {
        _lastUsedPaths = customPaths;
      } else {
        _lastUsedPaths = {..._lastUsedPaths!, ...customPaths}.toList();
      }
    }

    final previousCurrentId = _streamingMusic == null ? currentMusic?.id : null;
    final rememberedState = {
      for (final music in _musicList) music.filePath: music
    };
    final keepRememberedVisible =
        clearExisting && customPaths == null && _musicList.isNotEmpty;
    if (clearExisting && !keepRememberedVisible) {
      _musicList = [];
      _systemMusicCount = 0;
    }
    notifyListeners();

    Timer? throttleTimer;

    final scannedMusic = await MusicScannerService.startScanning(
      customPaths: customPaths ?? _lastUsedPaths,
      onBatchUpdate: (batch) {
        bool changed = false;
        for (final music in batch) {
          if (_isNonPrimaryDownloadedQuality(music.filePath)) continue;
          final existingIndex = _musicList
              .indexWhere((existing) => existing.filePath == music.filePath);
          if (existingIndex == -1) {
            _musicList.add(music);
            changed = true;
          } else {
            final refreshed =
                _mergeScannedTrackState(music, _musicList[existingIndex]);
            if (_shouldReplaceScannedTrack(
                _musicList[existingIndex], refreshed)) {
              _musicList[existingIndex] = refreshed;
              changed = true;
            }
          }
        }

        if (changed) {
          _musicList = _collapseDownloadedVideoQualitySets(_musicList);
          _systemMusicCount = _musicList.length;
          if (throttleTimer == null || !throttleTimer!.isActive) {
            notifyListeners();
            throttleTimer = Timer(const Duration(milliseconds: 500), () {});
          }
        }
      },
    );

    throttleTimer?.cancel();

    if (clearExisting && scannedMusic.isNotEmpty) {
      _musicList = _collapseDownloadedVideoQualitySets(
          _mergeRememberedTrackState(scannedMusic, rememberedState));
      _systemMusicCount = _musicList.length;
    } else {
      _musicList = _collapseDownloadedVideoQualitySets(_musicList);
      _systemMusicCount = _musicList.length;
    }

    await _loadStatsAsync();
    await _loadFavoritesAsync();

    _isLoadingSystemMusic = false;
    _syncQueueWithLibrary(previousCurrentId: previousCurrentId);
    _refreshSystemPlaylistsInternal();
    await _restorePlaybackStateIfNeeded();
    await _saveLibrarySnapshot();
    notifyListeners();
  }

  Future<int> importWebFolderMusic() async {
    if (!kIsWeb) return 0;

    final importedTracks = await pickWebFolderMusic();
    if (importedTracks.isEmpty) return 0;

    _streamingMusic = null;
    var added = 0;
    for (final track in importedTracks) {
      final exists = _musicList.any(
          (music) => music.id == track.id || music.filePath == track.filePath);
      if (exists) continue;
      _musicList.add(track);
      added++;
    }

    if (added == 0) return 0;
    _systemMusicCount = _musicList.length;
    _activeQueueIds = _musicList.map((music) => music.id).toList();
    _rebuildShuffledQueue();
    _refreshSystemPlaylistsInternal();
    await _saveLibrarySnapshot();
    notifyListeners();
    return added;
  }

  Future<int> importSharedMusicFiles(
    List<String> filePaths, {
    bool createBackup = true,
  }) async {
    if (filePaths.isEmpty || kIsWeb) return 0;

    final existingFilePaths = <String>[];
    for (final path in filePaths.toSet()) {
      if (await File(path).exists()) {
        existingFilePaths.add(path);
      }
    }
    if (existingFilePaths.isEmpty) return 0;

    if (createBackup) {
      await _backupLibraryBeforeShareImport();
    }
    final importedTracks =
        await MusicScannerService.createMusicListFromPaths(existingFilePaths);
    if (importedTracks.isEmpty) return 0;

    _streamingMusic = null;
    var added = 0;
    for (final track in importedTracks) {
      final exists =
          _musicList.any((music) => music.filePath == track.filePath);
      if (exists) continue;
      _musicList.add(_withUniqueImportedId(track));
      added++;
    }

    if (added == 0) return 0;
    _systemMusicCount = _musicList.length;
    _syncQueueWithLibrary();
    _refreshSystemPlaylistsInternal();
    await _saveLibrarySnapshot();
    notifyListeners();
    return added;
  }

  Music _withUniqueImportedId(Music track) {
    final hasSameId = _musicList.any(
      (music) => music.id == track.id && music.filePath != track.filePath,
    );
    if (!hasSameId) return track;

    final pathHash = track.filePath.hashCode.abs().toRadixString(16);
    final baseId = '${track.id}_sync_$pathHash';
    var candidateId = baseId;
    var counter = 1;
    while (_musicList.any((music) => music.id == candidateId)) {
      candidateId = '${baseId}_$counter';
      counter++;
    }

    return Music(
      id: candidateId,
      title: track.title,
      artist: track.artist,
      album: track.album,
      filePath: track.filePath,
      coverPath: track.coverPath,
      genre: track.genre,
      duration: track.duration,
      isFavorite: track.isFavorite,
      playCount: track.playCount,
      lastPlayed: track.lastPlayed,
      dateAdded: track.dateAdded,
    );
  }

  Future<void> _backupLibraryBeforeShareImport() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled =
          prefs.getBool(SettingsModel.shareSyncBackupsEnabledKey) ?? true;
      if (!enabled) return;

      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(dir.path, 'PlayerVF Sync Backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backupFile = File(p.join(backupDir.path, 'library_$stamp.json'));
      final payload = {
        'createdAt': DateTime.now().toIso8601String(),
        'reason': 'share_sync_import',
        'tracks': _musicList.map((music) => music.toJson()).toList(),
        'playlists': _playlists.map((playlist) => playlist.toJson()).toList(),
      };
      await backupFile.writeAsString(jsonEncode(payload));
    } catch (e) {
      debugPrint('Share sync backup failed: $e');
    }
  }

  Future<void> clearCache() async {
    _musicList = [];
    _systemMusicCount = 0;
    _activeQueueIds = [];
    _shuffledQueueIds = [];
    notifyListeners();
    await loadSystemMusic(customPaths: _lastUsedPaths);
  }

  void deleteMusic(int index) {
    if (index >= 0 && index < _musicList.length) {
      final removedId = _musicList[index].id;
      if (_openedMusicId == removedId) {
        _openedMusicId = null;
      }
      if (_resumeTrackId == removedId) {
        _clearResumeState();
      }
      _musicList.removeAt(index);
      if (_currentIndex >= _musicList.length) {
        _currentIndex = max(0, _musicList.length - 1);
      }
      _activeQueueIds.remove(removedId);
      _shuffledQueueIds.remove(removedId);
      _syncQueueWithLibrary();
      _savePlaybackDebounced();
      _saveLibrarySnapshot();
      notifyListeners();
    }
  }

  Future<void> updateMusicMetadata(String id, String title, String artist,
      String album, String genre) async {
    final index = _musicList.indexWhere((music) => music.id == id);
    if (index != -1) {
      final old = _musicList[index];
      _musicList[index] = Music(
        id: old.id,
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        filePath: old.filePath,
        coverPath: old.coverPath,
        duration: old.duration,
        isFavorite: old.isFavorite,
        playCount: old.playCount,
        lastPlayed: old.lastPlayed,
        dateAdded: old.dateAdded,
      );
      notifyListeners();
      _saveLibrarySnapshot();
    }
  }

  Future<void> updateMusicCover(String id, String coverPath) async {
    final index = _musicList.indexWhere((music) => music.id == id);
    if (index == -1) return;

    final old = _musicList[index];
    _musicList[index] = Music(
      id: old.id,
      title: old.title,
      artist: old.artist,
      album: old.album,
      genre: old.genre,
      filePath: old.filePath,
      coverPath: coverPath,
      duration: old.duration,
      isFavorite: old.isFavorite,
      playCount: old.playCount,
      lastPlayed: old.lastPlayed,
      dateAdded: old.dateAdded,
    );

    if (currentMusic?.id == id) {
      await _audioHandler.updateNowPlayingOnly(_musicList[index]);
    }

    notifyListeners();
    await _saveLibrarySnapshot();
  }

  void _refreshSystemPlaylistsInternal() {
    if (_musicList.isEmpty) return;

    final history = _musicList
        .where((music) => music.lastPlayed != null)
        .toList()
      ..sort((a, b) =>
          (b.lastPlayed ?? DateTime(0)).compareTo(a.lastPlayed ?? DateTime(0)));
    _cachedEarlyListened = history.take(10).toList();

    final topPlayed = _musicList.where((music) => music.playCount > 0).toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    _cachedMostListened = topPlayed.take(5).toList();
    _cachedDailyMix = _generateDailyMix();
  }

  void refreshSystemPlaylists() {
    _refreshSystemPlaylistsInternal();
    notifyListeners();
  }

  List<Music> _generateDailyMix() {
    if (_musicList.isEmpty) return [];

    final genreScores = <String, int>{};
    for (final music in _musicList) {
      if (music.playCount > 0) {
        genreScores[music.genre] =
            (genreScores[music.genre] ?? 0) + music.playCount;
      }
    }

    final sortedGenres = genreScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = sortedGenres.take(3).map((entry) => entry.key).toList();

    final mix = <Music>{};
    if (topGenres.isNotEmpty) {
      final genrePool = _musicList
          .where((music) => topGenres.contains(music.genre))
          .toList()
        ..shuffle();
      mix.addAll(genrePool.take(10));
    }

    final discoveryPool = List<Music>.from(_musicList)..shuffle();
    mix.addAll(discoveryPool.take(15));
    return mix.toList()..shuffle();
  }

  Future<void> createPlaylist(String name) async {
    _playlists.add(Playlist(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        musicIds: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now()));
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final index = _playlists.indexWhere((pl) => pl.id == id);
    if (index != -1) {
      _playlists[index] = Playlist(
        id: _playlists[index].id,
        name: newName,
        musicIds: _playlists[index].musicIds,
        createdAt: _playlists[index].createdAt,
        updatedAt: DateTime.now(),
      );
      await _savePlaylists();
      notifyListeners();
    }
  }

  void deletePlaylist(String id) {
    _playlists.removeWhere((playlist) => playlist.id == id);
    _savePlaylists();
    notifyListeners();
  }

  void addMusicToPlaylist(String playlistId, String musicId) {
    final playlist = _playlists.firstWhere((item) => item.id == playlistId);
    if (!playlist.musicIds.contains(musicId)) {
      playlist.musicIds.add(musicId);
      _savePlaylists();
      notifyListeners();
    }
  }

  void removeMusicFromPlaylist(String playlistId, String musicId) {
    final index = _playlists.indexWhere((item) => item.id == playlistId);
    if (index != -1) {
      _playlists[index].musicIds.remove(musicId);
      _savePlaylists();
      notifyListeners();
    }
  }

  void playPlaylist(String id) {
    final list = getMusicListForPlaylist(id);
    if (list.isNotEmpty) {
      unawaited(_runPlaybackCommand(() async {
        startQueue(list, startMusicId: list.first.id, playlistId: id);
        await play();
      }));
    }
  }

  void playMusicFromQueue(List<Music> queue, Music target,
      {String? playlistId}) {
    unawaited(_runPlaybackCommand(() async {
      startQueue(queue, startMusicId: target.id, playlistId: playlistId);
      await play();
    }));
  }

  Future<void> playStreamingMusic(Music music) async {
    _streamingMusic = music;
    _currentPlaylistId = null;
    _activeQueueIds = [music.id];
    _shuffledQueueIds = [music.id];
    _clearResumeState(keepOpenedTrack: false);
    notifyListeners();
    await _playStreamingCurrent();
  }

  Future<void> replaceStreamingMusic(
    Music music, {
    Duration? startPosition,
    bool? shouldPlay,
  }) async {
    final targetPosition = startPosition ?? _position;
    final playAfterOpen = shouldPlay ?? _isPlaying;
    _streamingMusic = music;
    _currentPlaylistId = null;
    _activeQueueIds = [music.id];
    _shuffledQueueIds = [music.id];
    _usingNativeWindowsAudio = false;
    _hasVideoTrack = false;
    _position = targetPosition;
    _positionNotifier.value = targetPosition;
    _duration = music.duration ?? _duration;
    _durationNotifier.value = _duration;
    _openedMusicId = null;
    notifyListeners();

    await _smoothOpenAndPlay(music, targetPosition);
    if (targetPosition > Duration.zero) {
      await _seekCurrentBackend(targetPosition);
      _position = targetPosition;
      _positionNotifier.value = targetPosition;
      unawaited(Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (_streamingMusic?.id == music.id) {
          unawaited(_seekCurrentBackend(targetPosition));
          _position = targetPosition;
          _positionNotifier.value = targetPosition;
        }
      }));
    }
    _openedMusicId = music.id;
    _resumeTrackId = music.id;
    _resumePosition = targetPosition;
    _shouldResumeCurrentTrack = targetPosition > Duration.zero;
    if (!playAfterOpen) {
      await _smoothPauseCurrentBackend();
    }
    _scheduleUpdate();
    notifyListeners();
  }

  void startQueue(List<Music> queue,
      {String? startMusicId, String? playlistId}) {
    _streamingMusic = null;
    final ids = queue
        .map((music) => music.id)
        .where((id) => _musicList.any((track) => track.id == id))
        .toList();
    if (ids.isEmpty) return;

    _activeQueueIds = ids;
    _currentPlaylistId = playlistId;
    final selectedId = startMusicId ?? ids.first;
    final actualIndex =
        _musicList.indexWhere((music) => music.id == selectedId);
    if (actualIndex != -1) {
      if (_musicList[actualIndex].id != currentMusic?.id) {
        _clearResumeState(keepOpenedTrack: false);
      }
      _currentIndex = actualIndex;
    }
    _rebuildShuffledQueue();
    _savePlaybackDebounced();
    notifyListeners();
  }

  void addToQueue(String musicId) {
    if (_streamingMusic != null) return;
    if (!_musicList.any((music) => music.id == musicId)) return;
    _ensureQueueInitialized();

    _activeQueueIds.remove(musicId);
    final currentId = currentMusic?.id;
    final insertIndex = currentId == null
        ? _activeQueueIds.length
        : _activeQueueIds.indexOf(currentId) + 1;
    final safeIndex = insertIndex.clamp(0, _activeQueueIds.length);
    _activeQueueIds.insert(safeIndex, musicId);
    _rebuildShuffledQueue();
    _savePlaybackDebounced();
    notifyListeners();
  }

  void removeFromQueue(String musicId) {
    if (_streamingMusic != null) return;
    if (_activeQueueIds.length <= 1) return;

    final currentId = currentMusic?.id;
    final wasCurrent = currentId == musicId;
    _activeQueueIds.remove(musicId);
    _shuffledQueueIds.remove(musicId);

    if (wasCurrent) {
      final nextId = _activeQueueIds.first;
      final nextIndex = _musicList.indexWhere((music) => music.id == nextId);
      if (nextIndex != -1) {
        _currentIndex = nextIndex;
        unawaited(_runPlaybackCommand(play));
        return;
      }
    }

    _rebuildShuffledQueue();
    _savePlaybackDebounced();
    notifyListeners();
  }

  void moveQueueItem(int oldIndex, int newIndex) {
    if (_streamingMusic != null) return;
    final order = _playbackOrderIds();
    if (order.isEmpty || oldIndex < 0 || oldIndex >= order.length) return;
    if (newIndex > order.length) newIndex = order.length;
    if (oldIndex < newIndex) newIndex -= 1;
    if (newIndex < 0 || newIndex >= order.length) return;

    final movedId = order.removeAt(oldIndex);
    order.insert(newIndex, movedId);
    _activeQueueIds = List<String>.from(order);
    if (_isShuffle) {
      _shuffledQueueIds = List<String>.from(order);
    }
    _savePlaybackDebounced();
    notifyListeners();
  }

  List<Music> getMusicListForPlaylist(String id) {
    if (id == 'favorites') return favoriteMusicList;
    if (id == 'most_listened') return _cachedMostListened;
    if (id == 'early_listened') return _cachedEarlyListened;
    if (id == 'daily_mix') return _cachedDailyMix;
    final playlist = _playlists.firstWhere(
      (item) => item.id == id,
      orElse: () => Playlist(
          id: '',
          name: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()),
    );
    return _musicList
        .where((music) => playlist.musicIds.contains(music.id))
        .toList();
  }

  Future<void> setRememberPlayback(bool value) async {
    _rememberPlayback = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberPlaybackKey, value);
    if (!value) {
      await prefs.remove(_playbackStateKey);
    } else {
      _savePlaybackDebounced();
    }
    notifyListeners();
  }

  Future<void> savePlaybackSnapshotNow() async {
    await _savePlaybackState();
  }

  Future<void> _loadSettingsAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEffectsEnabled = prefs.getBool(_effectsEnabledKey) ?? true;
      _isEqualizerEnabled = prefs.getBool(_equalizerEnabledKey) ?? false;
      _currentPreset = prefs.getString(_equalizerPresetKey) ?? 'Normal';
      if (!_eqPresets.containsKey(_currentPreset) &&
          _currentPreset != 'Custom') {
        _currentPreset = 'Normal';
      }
      _pitch = (prefs.getDouble(_pitchKey) ?? 1.0).clamp(0.5, 2.0).toDouble();
      _speed = (prefs.getDouble(_speedKey) ?? 1.0).clamp(0.5, 2.0).toDouble();
      _reverb = (prefs.getDouble(_reverbKey) ?? 0.0).clamp(0.0, 1.0).toDouble();
      _useSongSpecificSettings =
          prefs.getBool(_songSpecificSettingsKey) ?? false;
      _rememberPlayback = prefs.getBool(_rememberPlaybackKey) ?? true;
      _songGapDuration = _sanitizeSongGap(Duration(
        milliseconds: prefs.getInt(SettingsModel.songGapMsKey) ?? 0,
      ));
      final eqList = prefs.getStringList(_globalEqKey);
      if (eqList != null) {
        _globalEqValues = _normalizeEqValues(
          eqList.map((entry) => double.tryParse(entry) ?? 0.0).toList(),
        );
      }

      final savedSongSettings = prefs.getString(_songSettingsKey);
      if (savedSongSettings != null && savedSongSettings.isNotEmpty) {
        _songSettings =
            Map<String, dynamic>.from(jsonDecode(savedSongSettings));
      }

      final savedPlayback = prefs.getString(_playbackStateKey);
      if (savedPlayback != null && savedPlayback.isNotEmpty) {
        _pendingPlaybackState =
            Map<String, dynamic>.from(jsonDecode(savedPlayback));
      }

      if (kIsWeb) {
        notifyListeners();
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final playlistFile = File('${dir.path}/playlists.json');
      if (await playlistFile.exists()) {
        final data = jsonDecode(await playlistFile.readAsString()) as List;
        _playlists = data.map((json) => Playlist.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _loadStatsAsync() async {
    if (kIsWeb) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_stats.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as List;
        for (final item in data) {
          final index =
              _musicList.indexWhere((music) => music.id == item['id']);
          if (index != -1) {
            _musicList[index] = Music.fromBase(
              _musicList[index],
              item['playCount'] ?? 0,
              item['lastPlayed'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(item['lastPlayed'])
                  : null,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  Future<void> _loadFavoritesAsync() async {
    if (kIsWeb) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/favorites.json');
      if (await file.exists()) {
        final ids = jsonDecode(await file.readAsString()).cast<String>();
        for (final music in _musicList) {
          music.isFavorite = ids.contains(music.id);
        }
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
    }
  }

  void _saveDebounced() {
    _saveSettingsTimer?.cancel();
    _saveSettingsTimer =
        Timer(const Duration(seconds: 2), _saveAudioEffectsSettings);
  }

  void _savePlaybackDebounced() {
    if (!_rememberPlayback) return;
    _savePlaybackTimer?.cancel();
    _savePlaybackTimer =
        Timer(const Duration(milliseconds: 800), _savePlaybackState);
  }

  Future<void> _saveAudioEffectsSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_effectsEnabledKey, _isEffectsEnabled);
      await prefs.setBool(_equalizerEnabledKey, _isEqualizerEnabled);
      await prefs.setString(_equalizerPresetKey, _currentPreset);
      await prefs.setDouble(_pitchKey, _pitch);
      await prefs.setDouble(_speedKey, _speed);
      await prefs.setDouble(_reverbKey, _reverb);
      await prefs.setBool(_songSpecificSettingsKey, _useSongSpecificSettings);
      await prefs.setString(_songSettingsKey, jsonEncode(_songSettings));
      await prefs.setStringList(
          _globalEqKey, _globalEqValues.map((e) => e.toString()).toList());
    } catch (e) {
      debugPrint('Error saving audio effects: $e');
    }
  }

  Future<void> _savePlaybackState() async {
    if (!_rememberPlayback) return;
    if (_streamingMusic != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'currentMusicId': currentMusic?.id,
        'queueIds': _activeQueueIds,
        'playlistId': _currentPlaylistId,
        'positionMs': _position.inMilliseconds,
        'shuffle': _isShuffle,
        'repeatOne': _isRepeatOne,
        'repeatAll': _isRepeatAll,
        'wasPlaying': _isPlaying,
        'shouldResumeCurrentTrack': _shouldResumeCurrentTrack,
      };
      await prefs.setString(_playbackStateKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('Error saving playback state: $e');
    }
  }

  Future<void> _applyResumePositionIfNeeded(String trackId) async {
    if (!_shouldResumeCurrentTrack ||
        _resumeTrackId != trackId ||
        _resumePosition <= Duration.zero) {
      return;
    }

    final currentDelta = (_position - _resumePosition).inMilliseconds.abs();
    if (currentDelta < 800) {
      return;
    }

    try {
      await _seekCurrentBackend(_resumePosition);
      _position = _resumePosition;
      _positionNotifier.value = _resumePosition;
    } catch (e) {
      debugPrint('Error applying resume position: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _savePlaybackState();
    }
  }

  Future<void> toggleFavorite(String id) async {
    final index = _musicList.indexWhere((music) => music.id == id);
    if (index != -1) {
      final old = _musicList[index];
      _musicList[index] = Music(
        id: old.id,
        title: old.title,
        artist: old.artist,
        album: old.album,
        filePath: old.filePath,
        coverPath: old.coverPath,
        genre: old.genre,
        duration: old.duration,
        isFavorite: !old.isFavorite,
        playCount: old.playCount,
        lastPlayed: old.lastPlayed,
        dateAdded: old.dateAdded,
      );
      notifyListeners();
      await _saveLibrarySnapshot();
      if (kIsWeb) return;
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/favorites.json');
        final ids = _musicList
            .where((music) => music.isFavorite)
            .map((music) => music.id)
            .toList();
        await file.writeAsString(jsonEncode(ids));
      } catch (e) {
        debugPrint('Error saving favorite: $e');
      }
    }
  }

  Future<void> _savePlaylists() async {
    if (kIsWeb) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/playlists.json');
      await file.writeAsString(
          jsonEncode(_playlists.map((playlist) => playlist.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving playlists: $e');
    }
  }

  Future<void> _saveStats() async {
    await _saveLibrarySnapshot();
    if (kIsWeb) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_stats.json');
      await file.writeAsString(
          jsonEncode(_musicList.map((music) => music.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving stats: $e');
    }
  }

  Future<void> _loadLibrarySnapshotAsync() async {
    try {
      String? raw;
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_librarySnapshotKey);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/music_library_snapshot.json');
        if (await file.exists()) raw = await file.readAsString();
      }

      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final tracks = decoded
          .whereType<Map>()
          .map((item) => Music.fromJson(Map<String, dynamic>.from(item)))
          .where((music) =>
              music.id.isNotEmpty &&
              music.filePath.isNotEmpty &&
              !_isTransientWebPath(music.filePath))
          .toList();
      if (tracks.isEmpty) return;

      _musicList = tracks;
      _systemMusicCount = tracks.length;
      _syncQueueWithLibrary();
      _refreshSystemPlaylistsInternal();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading music snapshot: $e');
    }
  }

  Future<void> _saveLibrarySnapshot() async {
    try {
      final tracks = _musicList
          .where((music) => !_isTransientWebPath(music.filePath))
          .map((music) => music.toJson())
          .toList();
      final raw = jsonEncode(tracks);

      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_librarySnapshotKey, raw);
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_library_snapshot.json');
      await file.writeAsString(raw);
    } catch (e) {
      debugPrint('Error saving music snapshot: $e');
    }
  }

  List<Music> _mergeRememberedTrackState(
    List<Music> scanned,
    Map<String, Music> remembered,
  ) {
    return scanned.map((music) {
      final old = remembered[music.filePath];
      if (old == null) return music;
      return _mergeScannedTrackState(music, old);
    }).toList();
  }

  Music _mergeScannedTrackState(Music scanned, Music old) {
    final base = Music(
      id: scanned.id,
      title: scanned.title,
      artist: scanned.artist,
      album: scanned.album,
      filePath: scanned.filePath,
      coverPath:
          scanned.coverPath.isNotEmpty ? scanned.coverPath : old.coverPath,
      genre: scanned.genre,
      duration: scanned.duration ?? old.duration,
      isFavorite: old.isFavorite,
      dateAdded: old.dateAdded,
    );
    return Music.fromBase(base, old.playCount, old.lastPlayed);
  }

  bool _shouldReplaceScannedTrack(Music old, Music refreshed) {
    return old.title != refreshed.title ||
        old.artist != refreshed.artist ||
        old.album != refreshed.album ||
        old.genre != refreshed.genre ||
        old.coverPath != refreshed.coverPath ||
        old.duration?.inMilliseconds != refreshed.duration?.inMilliseconds;
  }

  bool _isTransientWebPath(String path) => path.startsWith('blob:');

  List<Music> _collapseDownloadedVideoQualitySets(List<Music> tracks) {
    final result = <Music>[];
    final seenManifestPaths = <String>{};
    for (final track in tracks) {
      final manifest = _readPlayervfVideoManifest(track.filePath);
      if (manifest == null) {
        result.add(track);
        continue;
      }

      if (seenManifestPaths.contains(manifest.path)) continue;
      seenManifestPaths.add(manifest.path);
      final primary = tracks.firstWhere(
        (item) => p.equals(
            p.normalize(item.filePath), p.normalize(manifest.primaryPath)),
        orElse: () => track,
      );
      result.add(primary);
    }
    return result;
  }

  bool _isNonPrimaryDownloadedQuality(String filePath) {
    final manifest = _readPlayervfVideoManifest(filePath);
    if (manifest == null) return false;
    return !p.equals(p.normalize(filePath), p.normalize(manifest.primaryPath));
  }

  _PlayervfVideoManifest? _readPlayervfVideoManifest(String filePath) {
    final manifestFile = _findPlayervfVideoManifestFile(filePath);
    if (manifestFile == null) return null;
    try {
      final decoded =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      if (decoded['type'] != 'playervf.youtubeVideoSet') return null;
      final qualities = decoded['qualities'] as List? ?? const [];
      if (qualities.isEmpty || qualities.first is! Map) return null;
      final primary =
          Map<String, dynamic>.from(qualities.first as Map<dynamic, dynamic>);
      final primaryPath = primary['path']?.toString() ?? '';
      if (primaryPath.isEmpty) return null;
      return _PlayervfVideoManifest(
        path: p.normalize(manifestFile.path),
        primaryPath: primaryPath,
      );
    } catch (_) {
      return null;
    }
  }

  File? _findPlayervfVideoManifestFile(String filePath) {
    final direct = File('${p.withoutExtension(filePath)}.playervf.json');
    if (direct.existsSync()) return direct;
    final dir = p.dirname(filePath);
    final stem = p.basenameWithoutExtension(filePath);
    final baseStem =
        stem.replaceFirst(RegExp(r'\.(auto|\d+p)$', caseSensitive: false), '');
    final grouped = File(p.join(dir, '$baseStem.playervf.json'));
    if (grouped.existsSync()) return grouped;
    return null;
  }

  List<int> getEqualizerFrequencies() => _eqFreqs;
  List<String> getEqualizerPresets() => _eqPresets.keys.toList();

  bool isFavorite(String id) {
    try {
      final music = _musicList.firstWhere((item) => item.id == id);
      return music.isFavorite;
    } catch (_) {
      return false;
    }
  }

  List<String> _playbackOrderIds() {
    _ensureQueueInitialized();
    if (_isShuffle) {
      if (_shuffledQueueIds.isEmpty) {
        _rebuildShuffledQueue();
      }
      return List<String>.from(_shuffledQueueIds);
    }
    return List<String>.from(_activeQueueIds);
  }

  List<Music> _resolveMusicIds(List<String> ids) {
    final tracks = <Music>[];
    for (final id in ids) {
      final index = _musicList.indexWhere((music) => music.id == id);
      if (index != -1) {
        tracks.add(_musicList[index]);
      }
    }
    return tracks;
  }

  void _ensureQueueInitialized() {
    if (_activeQueueIds.isEmpty && _musicList.isNotEmpty) {
      _activeQueueIds = _musicList.map((music) => music.id).toList();
      _rebuildShuffledQueue();
    }
  }

  void _rebuildShuffledQueue() {
    final baseQueue = List<String>.from(_activeQueueIds);
    if (baseQueue.isEmpty) {
      _shuffledQueueIds = [];
      return;
    }

    final currentId = currentMusic?.id;
    baseQueue.remove(currentId);
    baseQueue.shuffle();
    _shuffledQueueIds = [
      if (currentId != null) currentId,
      ...baseQueue,
    ];
  }

  bool _moveInQueue(int direction) {
    if (_musicList.isEmpty) return false;
    final order = _playbackOrderIds();
    if (order.isEmpty) return false;

    final currentId = currentMusic?.id;
    var queueIndex = currentId == null ? -1 : order.indexOf(currentId);
    if (queueIndex == -1) queueIndex = 0;

    final targetIndex = queueIndex + direction;
    if (targetIndex < 0) {
      if (!_isRepeatAll) return false;
      final loopIndex =
          _musicList.indexWhere((music) => music.id == order.last);
      if (loopIndex == -1) return false;
      _currentIndex = loopIndex;
      return true;
    }

    if (targetIndex >= order.length) {
      if (!_isRepeatAll) {
        unawaited(_pauseCurrentBackend());
        _openedMusicId = currentMusic?.id;
        _resumeTrackId = currentMusic?.id;
        _resumePosition = Duration.zero;
        seekTo(Duration.zero);
        return false;
      }
      final loopIndex =
          _musicList.indexWhere((music) => music.id == order.first);
      if (loopIndex == -1) return false;
      _currentIndex = loopIndex;
      return true;
    }

    final actualIndex =
        _musicList.indexWhere((music) => music.id == order[targetIndex]);
    if (actualIndex == -1) return false;
    _currentIndex = actualIndex;
    return true;
  }

  Future<void> _handleTrackCompleted() async {
    if (_isRepeatOne) {
      seekTo(Duration.zero);
      await play();
      return;
    }

    if (_moveInQueue(1)) {
      await play();
      return;
    }

    unawaited(_pauseCurrentBackend());
    seekTo(Duration.zero);
    notifyListeners();
  }

  Future<void> _handleBackendCompleted() async {
    final trackId = currentMusic?.id;
    if (trackId == null || _completedTrackId == trackId) return;

    _completedTrackId = trackId;
    await _runPlaybackCommand(_handleTrackCompleted);
  }

  void _syncQueueWithLibrary({String? previousCurrentId}) {
    final validIds = _musicList.map((music) => music.id).toSet();
    _activeQueueIds = _activeQueueIds.where(validIds.contains).toList();
    if (_activeQueueIds.isEmpty) {
      _activeQueueIds = _musicList.map((music) => music.id).toList();
    }

    final currentId = currentMusic?.id ?? previousCurrentId;
    if (currentId != null) {
      final actualIndex =
          _musicList.indexWhere((music) => music.id == currentId);
      if (actualIndex != -1) {
        _currentIndex = actualIndex;
      }
    }

    if (_currentIndex >= _musicList.length) {
      _currentIndex = max(0, _musicList.length - 1);
    }
    _rebuildShuffledQueue();
  }

  Future<void> _restorePlaybackStateIfNeeded() async {
    if (_hasRestoredPlayback ||
        !_rememberPlayback ||
        _pendingPlaybackState == null ||
        _musicList.isEmpty) {
      return;
    }

    final state = _pendingPlaybackState!;
    final queueIds = (state['queueIds'] as List?)
            ?.map((item) => item.toString())
            .where((id) => _musicList.any((music) => music.id == id))
            .toList() ??
        [];
    _activeQueueIds = queueIds.isNotEmpty
        ? queueIds
        : _musicList.map((music) => music.id).toList();

    _currentPlaylistId = state['playlistId'] as String?;
    _isShuffle = state['shuffle'] == true;
    _isRepeatOne = state['repeatOne'] == true;
    _isRepeatAll = state['repeatAll'] != false;
    _shouldResumeCurrentTrack = state['shouldResumeCurrentTrack'] != false;

    final currentId = state['currentMusicId']?.toString();
    if (currentId != null) {
      final restoredIndex =
          _musicList.indexWhere((music) => music.id == currentId);
      if (restoredIndex != -1) {
        _currentIndex = restoredIndex;
      }
    }

    _rebuildShuffledQueue();
    _hasRestoredPlayback = true;
    _pendingPlaybackState = null;

    try {
      await _openTrackMedia(_musicList[_currentIndex]);
      _openedMusicId = _musicList[_currentIndex].id;
      final positionMs = state['positionMs'] as int? ?? 0;
      if (positionMs > 0) {
        final restoredPosition = Duration(milliseconds: positionMs);
        await _seekCurrentBackend(restoredPosition);
        _position = restoredPosition;
        _positionNotifier.value = restoredPosition;
        _resumeTrackId = _musicList[_currentIndex].id;
        _resumePosition = restoredPosition;
      } else {
        _resumeTrackId = _musicList[_currentIndex].id;
        _resumePosition = Duration.zero;
        _shouldResumeCurrentTrack = false;
      }
      if (state['wasPlaying'] == true) {
        await _playCurrentBackend();
        _shouldResumeCurrentTrack = false;
      }
    } catch (e) {
      debugPrint('Error restoring playback state: $e');
    }
  }

  void _clearResumeState({bool keepOpenedTrack = true}) {
    _resumeTrackId = null;
    _resumePosition = Duration.zero;
    _shouldResumeCurrentTrack = false;
    if (!keepOpenedTrack) {
      _openedMusicId = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveSettingsTimer?.cancel();
    unawaited(_saveAudioEffectsSettings());
    _savePlaybackState();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_clearNowPlaying());
    unawaited(_mediaPlayer.dispose());
    unawaited(_retiringPlayer?.dispose());
    _audioHandler
      ..onTogglePlayPauseCommand = null
      ..onPlayCommand = null
      ..onPauseCommand = null
      ..onNextCommand = null
      ..onPreviousCommand = null
      ..onSeekCommand = null
      ..onCompleted = null;
    _savePlaybackTimer?.cancel();
    _effectsUpdateTimer?.cancel();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _playingNotifier.dispose();
    super.dispose();
  }
}

class _PlayervfVideoManifest {
  final String path;
  final String primaryPath;

  const _PlayervfVideoManifest({
    required this.path,
    required this.primaryPath,
  });
}

class _LyricsQuery {
  final String trackName;
  final String artistName;
  final String? albumName;
  final int? durationSeconds;

  const _LyricsQuery({
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.durationSeconds,
  });
}

class _ScoredLrclibLyrics {
  final LrclibLyrics lyrics;
  final int score;

  const _ScoredLrclibLyrics({
    required this.lyrics,
    required this.score,
  });
}

class LrclibLyrics {
  final int? id;
  final String? trackName;
  final String? artistName;
  final String? albumName;
  final int? durationSeconds;
  final String? syncedLyrics;
  final String? plainLyrics;

  const LrclibLyrics({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.durationSeconds,
    required this.syncedLyrics,
    required this.plainLyrics,
  });

  bool get hasLyrics =>
      (syncedLyrics != null && syncedLyrics!.trim().isNotEmpty) ||
      (plainLyrics != null && plainLyrics!.trim().isNotEmpty);

  bool get hasSyncedLyrics =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;

  bool get hasPlainLyrics =>
      plainLyrics != null && plainLyrics!.trim().isNotEmpty;

  factory LrclibLyrics.fromJson(Map<String, dynamic> json) {
    return LrclibLyrics(
      id: (json['id'] as num?)?.toInt(),
      trackName: json['trackName']?.toString(),
      artistName: json['artistName']?.toString(),
      albumName: json['albumName']?.toString(),
      durationSeconds: (json['duration'] as num?)?.round(),
      syncedLyrics: json['syncedLyrics']?.toString(),
      plainLyrics: json['plainLyrics']?.toString(),
    );
  }
}
