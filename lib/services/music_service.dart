import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:crypto/crypto.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/lyrics_model.dart';
import '../models/music_model.dart';
import '../models/playback_snapshot.dart';
import '../models/playlist_model.dart';
import '../models/settings_model.dart';
import 'app_directories.dart';
import 'music_scanner_service.dart';
import 'player_audio_handler.dart';
import 'user_feedback_store.dart';
import 'video_playback_service.dart';
import 'web_folder_picker.dart';

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
  static const String _effectsEnabledKey = 'master_eff';
  static const String _equalizerEnabledKey = 'eq_enabled';
  static const String _equalizerPresetKey = 'eq_preset';
  static const String _globalEqKey = 'glob_eq';
  static const String _pitchKey = 'pitch_eff';
  static const String _speedKey = 'speed_eff';
  static const String _reverbKey = 'reverb_eff';
  static const String _songSettingsKey = 'song_eff_map';
  static const String _songSpecificSettingsKey = 'song_specific_eff';
  static const String _safeEarsEnabledKey = 'safe_ears_enabled';
  static const String _safeEarsMaxVolumeKey = 'safe_ears_max_volume';
  static const String _dspEnabledKey = 'dsp_enabled';
  static const String _dspLoudnessKey = 'dsp_loudness';
  static const String _dspLimiterKey = 'dsp_limiter';
  static const String _dspCompressorKey = 'dsp_compressor';
  static const String _dspBassKey = 'dsp_bass';
  static const String _dspMidKey = 'dsp_mid';
  static const String _dspTrebleKey = 'dsp_treble';
  static const Duration _manualCrossfadeDuration = Duration(milliseconds: 340);
  static const Duration _singlePlayerFadeOutDuration =
      Duration(milliseconds: 180);
  static const Duration _singlePlayerFadeInDuration =
      Duration(milliseconds: 240);
  static const Duration _playFadeInDuration = Duration(milliseconds: 220);
  static const Duration _pauseFadeOutDuration = Duration(milliseconds: 180);
  static const bool _debugPlayback = true;
  List<Music> _musicList = [];
  Music? _streamingMusic;
  List<Music> _streamingQueue = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final PlayerAudioHandler _audioHandler;
  late Player _mediaPlayer;
  late final VideoPlaybackService _videoPlayback;
  double _volume = 100.0;

  final ValueNotifier<Duration> _positionNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _songGapRemainingNotifier =
      ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _playingNotifier = ValueNotifier(false);
  final ValueNotifier<double> _volumeNotifier = ValueNotifier(100.0);
  final ValueNotifier<PlaybackSnapshot> _snapshotNotifier =
      ValueNotifier(PlaybackSnapshot.empty);

  ValueNotifier<PlaybackSnapshot> get snapshotNotifier => _snapshotNotifier;

  bool _isInitialized = false;
  DateTime _lastPositionUpdate = DateTime.now();
  DateTime _lastExternalPlaybackUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPlaybackPersistUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  bool _suppressPositionUpdatesForTrackChange = false;
  Timer? _saveSettingsTimer;
  Timer? _savePlaybackTimer;
  bool _settingsDirty = false;
  bool _playbackDirty = false;
  Timer? _songGapCountdownTimer;
  Timer? _linuxExternalPlaybackTimer;
  Timer? _nativeAudioProgressTimer;
  DateTime? _nativeAudioLastProgressTick;
  Process? _linuxExternalProcess;
  bool _usingLinuxExternalPlayback = false;

  List<String> _activeQueueIds = [];
  List<String> _shuffledQueueIds = [];
  bool _isShuffle = false;
  bool _isLoadingSystemMusic = false;
  int _systemMusicCount = 0;
  int _dataVersion = 0;
  List<Music>? _cachedRecommended;
  int _recommendedVersion = -1;
  LibraryStatsDashboard? _cachedStats;
  int _statsVersion = -1;
  int _recommendationRefreshSeed = DateTime.now().millisecondsSinceEpoch;

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
  DateTime? _lastTrackOpenStartedAt;
  Map<String, dynamic>? _pendingPlaybackState;
  String? _openedMusicId;
  String? _resumeTrackId;
  Duration _resumePosition = Duration.zero;
  bool _shouldResumeCurrentTrack = false;
  bool _isEffectsEnabled = true;
  bool _isEqualizerEnabled = false;
  List<double> _globalEqValues = List.filled(10, 0.0);
  String _currentPreset = 'Normal';
  bool _safeEarsEnabled = false;
  double _safeEarsMaxVolume = 72.0;
  double _lastAudibleVolume = 70.0;
  bool _dspEnabled = true;
  bool _dspLoudnessNormalizationEnabled = true;
  bool _dspLimiterEnabled = true;
  bool _dspCompressorEnabled = false;
  double _dspBass = 0.0;
  double _dspMid = 0.0;
  double _dspTreble = 0.0;
  double _pitch = 1.0;
  double _speed = 1.0;
  double _reverb = 0.0;
  double _effectsVolumeFactor = 1.0;
  Map<String, dynamic> _songSettings = {};
  bool _useSongSpecificSettings = false;

  bool _isUpdatingEffects = false;
  bool _hasPendingUpdate = false;
  bool _supportsPitchControl =
      kIsWeb || !(Platform.isWindows || Platform.isLinux);
  Timer? _effectsUpdateTimer;
  int _effectsUpdateGeneration = 0;
  String? _lastNativeAudioFilterKey;
  double? _lastLoggedPcEqVolumeFactor;
  DecoderMode _audioDecoderMode = DecoderMode.auto;
  DecoderMode _videoDecoderMode = DecoderMode.auto;
  int _audioTransitionGeneration = 0;
  int _volumeChangeGeneration = 0;
  bool _usingNativeWindowsAudio = false;
  Future<void> _mediaOpenQueue = Future<void>.value();
  bool _windowsMediaControlForeground = true;
  bool _windowsMediaControlOwned = false;
  static const MethodChannel _windowsMediaControlChannel =
      MethodChannel('player_vf_media_controls');
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
    'Pop': [1, 5, 8, 10, 9, 7, 3, 0, 1, 2],
    'Rock': [10, 9, 6, 1, -3, -2, 1, 5, 8, 9],
    'Jazz': [5, 4, 2, 3, -2, -3, 0, 2, 4, 5],
    'Classical': [5, 4, 3, 1, -1, -1, 0, 2, 3, 4],
    'Bass Boost': [12, 12, 10, 7, 4, 1, -1, -3, -6, -8],
    'Soft Bass': [5, 7, 5, -2, -8, -5, 0, 2, -3, -10],
    'Treble Boost': [-4, -3, -2, -1, 0, 2, 5, 8, 10, 12],
    'Electronic': [6, 7, 6, 3, 0, -2, 1, 4, 4, 2],
    'Techno': [6, 7, 7, 5, 2, -2, 0, 3, 4, 2],
    'Dance': [7, 8, 6, 2, 0, 2, 5, 6, 5, 4],
    'Club': [6, 6, 4, 1, 0, 2, 5, 6, 4, 2],
    'Hip Hop': [9, 8, 6, 2, -1, -3, 0, 2, 3, 4],
    'R&B': [6, 7, 5, 2, -1, 0, 1, 3, 4, 5],
    'Metal': [5, 5, 5, 2, -1, -2, 0, 1, -1, -1],
    'Heavy Metal': [8, 7, 5, 2, -2, -2, 1, 4, 7, 9],
    'Acoustic': [4, 3, 2, 1, 2, 2, 3, 4, 3, 2],
    'Vocal': [-3, -2, 0, 4, 7, 7, 4, 1, -2, -4],
    'Podcast': [-5, -4, -2, 3, 7, 7, 4, 0, -3, -5],
    'Loudness': [-10, -7, 0, 3, 4, 5, 3, -3, -5, -3],
    'Deep': [10, 9, 7, 4, 1, -2, -3, -3, -2, 0],
    'Bright': [-3, -2, -1, 1, 2, 4, 6, 8, 10, 11],
    'Clear': [1, 1, 0, -1, -2, 0, 0, 1, 2, 2],
    'Soft Clear': [0, -10, -6, -2, 0, 0, 0, 0, 6, 10],
    'Presence': [0, 0, 1, 3, 5, 6, 5, 3, 1, 0],
    'Punch & Sparkle': [3, 5, 2, -2, -5, -4, -1, 2, 4, 5],
    'Car Stereo': [5, 4, 2, -1, -3, -3, 0, 3, 5, 4],
    'Home Theater': [5, 2, 0, -3, -5, -6, -2, 2, 4, 2],
    'Air': [-2, -2, -1, 0, 1, 2, 4, 7, 10, 12],
    'Shimmer': [-3, -2, -1, 0, 1, 2, 5, 8, 11, 12],
    'Warm': [5, 4, 3, 1, 0, -1, -1, 0, 1, 2],
    'Movie': [7, 5, 2, -1, -3, 0, 3, 6, 7, 8],
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
    _mediaPlayer = _createPlayer();
    _videoPlayback = VideoPlaybackService(
      player: _mediaPlayer,
      videoDecoderMode: () => _videoDecoderMode,
      debug: _playbackDebug,
      onChanged: notifyListeners,
    );
    _bindPlayer(_mediaPlayer);
    if (!kIsWeb && Platform.isWindows) {
      _windowsMediaControlChannel.setMethodCallHandler(
        _handleWindowsMediaControlCall,
      );
    }
    _initializeAsync();
  }

  Player _createPlayer() {
    if (!kIsWeb && Platform.isLinux) {
      return Player(
        configuration: const PlayerConfiguration(
          pitch: false,
          title: 'PlayerVF',
        ),
      );
    }
    return Player();
  }

  void _bindPlayer(Player player) {
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _playerSubscriptions.clear();
    _mediaPlayer = player;
    _videoPlayback.attachPlayer(player);
    _initPlayer();
  }

  Future<void> _ensureVideoControllerForCurrentTrack() async {
    await _videoPlayback.ensureControllerForCurrentTrack();
  }

  Future<void> _initializeAsync() async {
    await _loadSettingsAsync();
    await _loadDecoderSettingsAsync();
    await _applyStartupAudioSettings();
    await _loadLibrarySnapshotAsync();
    _isInitialized = true;
    notifyListeners();
    unawaited(_refreshLibraryAfterFirstFrame());
  }

  Future<void> _applyStartupAudioSettings() async {
    if (_safeEarsEnabled && _volume > _safeEarsMaxVolume) {
      _volume = _safeEarsMaxVolume.clamp(35.0, 100.0).toDouble();
      _volumeNotifier.value = _volume;
      _lastAudibleVolume = _volume;
    }
    try {
      await _setOutputVolume(_volume);
      await _audioHandler.setVolumeFromService(
        _effectiveBackendVolume(_volume) / 100.0,
      );
      _scheduleUpdate(delay: const Duration(milliseconds: 20));
    } catch (e) {
      debugPrint('Error applying startup audio settings: $e');
    }
  }

  Future<void> _refreshLibraryAfterFirstFrame() async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (_isLoadingSystemMusic) return;
    await loadSystemMusic(clearExisting: false);
  }

  void _initPlayer() {
    final player = _mediaPlayer;
    int? videoStreamWidth;
    int? videoStreamHeight;

    void syncVideoSurfaceSize(String reason) {
      _videoPlayback.updateSurfaceSize(
        width: videoStreamWidth,
        height: videoStreamHeight,
        reason: reason,
      );
    }

    _playerSubscriptions.add(player.stream.position.listen((pos) {
      if (_suppressPositionUpdatesForTrackChange) return;

      final now = DateTime.now();
      if (now.difference(_lastPositionUpdate).inMilliseconds > 90) {
        _position = pos;
        _positionNotifier.value = pos;
        _updateSnapshot();
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

    _playerSubscriptions.add(player.stream.width.listen((width) {
      videoStreamWidth = width;
      _playbackDebug('stream.width=$width');
      syncVideoSurfaceSize('stream.width');
    }));

    _playerSubscriptions.add(player.stream.height.listen((height) {
      videoStreamHeight = height;
      _playbackDebug('stream.height=$height');
      syncVideoSurfaceSize('stream.height');
    }));

    _playerSubscriptions.add(player.stream.videoParams.listen((params) {
      final width = params.dw ?? params.w;
      final height = params.dh ?? params.h;
      if (width != null && height != null) {
        videoStreamWidth = width;
        videoStreamHeight = height;
        _playbackDebug(
          'stream.videoParams=${width}x$height raw=${params.w}x${params.h} rotate=${params.rotate}',
        );
        syncVideoSurfaceSize('stream.videoParams');
      }
    }));

    _playerSubscriptions.add(player.stream.playing.listen((state) {
      _playbackDebug('stream.playing=$state');
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
      _playbackDebug('stream.completed=$done');
      if (!done) return;
      unawaited(_handleBackendCompleted());
    }));

    _playerSubscriptions.add(_audioHandler.positionStream.listen((pos) {
      if (!_usingNativeWindowsAudio || _suppressPositionUpdatesForTrackChange) {
        return;
      }
      _applyNativeAudioPosition(pos);
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
      if (state) {
        _startNativeAudioProgressTicker();
      } else {
        _stopNativeAudioProgressTicker(syncPosition: true);
      }
      _syncExternalPlaybackState(playing: state, position: _position);
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

  Future<dynamic> _handleWindowsMediaControlCall(MethodCall call) async {
    if (call.method != 'control') return null;
    final args = call.arguments;
    final command = args is Map ? args['command']?.toString() : null;
    switch (command) {
      case 'playPause':
        await _handleSystemTogglePlayPause();
        break;
      case 'play':
        await _handleSystemPlay();
        break;
      case 'pause':
      case 'stop':
        await _handleSystemPause();
        break;
      case 'next':
        await _handleSystemNext();
        break;
      case 'previous':
        await _handleSystemPrevious();
        break;
      case 'volumeUp':
        adjustVolumeBy(5);
        break;
      case 'volumeDown':
        adjustVolumeBy(-5);
        break;
      case 'volumeMute':
        toggleMute();
        break;
    }
    return null;
  }

  void _syncWindowsMediaControlOwnership() {
    if (kIsWeb || !Platform.isWindows) return;
    final shouldOwn = _windowsMediaControlForeground || _isPlaying;
    if (shouldOwn == _windowsMediaControlOwned) return;
    _windowsMediaControlOwned = shouldOwn;
    unawaited(_windowsMediaControlChannel.invokeMethod('setOwnership', {
      'active': _windowsMediaControlForeground,
      'playing': _isPlaying,
    }).catchError((_) {}));
  }

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
  ValueNotifier<Duration> get songGapRemainingNotifier =>
      _songGapRemainingNotifier;
  ValueNotifier<bool> get playingNotifier => _playingNotifier;
  ValueNotifier<double> get volumeNotifier => _volumeNotifier;
  double get volume => _volume;
  bool get isLoadingSystemMusic => _isLoadingSystemMusic;
  int get systemMusicCount => _systemMusicCount;
  List<Playlist> get playlists => _playlists;
  bool get isShuffle => _isShuffle;
  VideoController? get videoController => _videoPlayback.controller;
  bool get videoControllerReady => _videoPlayback.controllerReady;
  bool get hasVideoTrack => _videoPlayback.hasVideoTrack;
  DecoderMode get audioDecoderMode => _audioDecoderMode;
  DecoderMode get videoDecoderMode => _videoDecoderMode;

  bool get isCurrentMediaVideo {
    final music = currentMusic;
    if (music == null) return false;
    return _isVideoTrack(music);
  }

  bool isVideoMedia(Music music) => _isVideoTrack(music);

  bool _isVideoTrack(Music music) => _videoPlayback.isVideoTrack(music);

  bool _shouldOpenLinuxVideoExternally(Music track) {
    return false;
  }

  bool _shouldOpenLinuxAudioExternally(Music track) {
    if (kIsWeb || !Platform.isLinux || _isVideoTrack(track)) return false;
    final path = track.filePath.trim().toLowerCase();
    final isRemote = path.startsWith('http://') || path.startsWith('https://');
    return isRemote && track.genre == 'YouTube Music';
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

  Map<String, dynamic> _mediaExtras(Music track) {
    return {
      'title': _metadataTitle(track),
      'artist': _metadataArtist(track),
      'album': track.album,
      'artwork': track.coverPath,
    };
  }

  bool get isRepeatOne => _isRepeatOne;
  bool get isRepeatAll => _isRepeatAll;
  bool get isEffectsEnabled => _isEffectsEnabled;
  bool get isEqualizerEnabled => _isEqualizerEnabled;
  bool get safeEarsEnabled => _safeEarsEnabled;
  double get safeEarsMaxVolume => _safeEarsMaxVolume;
  bool get dspEnabled => _dspEnabled;
  bool get dspLoudnessNormalizationEnabled => _dspLoudnessNormalizationEnabled;
  bool get dspLimiterEnabled => _dspLimiterEnabled;
  bool get dspCompressorEnabled => _dspCompressorEnabled;
  double get dspBass => _dspBass;
  double get dspMid => _dspMid;
  double get dspTreble => _dspTreble;
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
      ? List<Music>.unmodifiable(
          _streamingQueue.isEmpty ? [_streamingMusic!] : _streamingQueue,
        )
      : _resolveMusicIds(_playbackOrderIds());
  int get currentQueuePosition {
    if (_streamingMusic != null) {
      return queueMusicList.indexWhere(
        (music) => _queueKey(music) == _queueKey(_streamingMusic!),
      );
    }
    final current = currentMusic;
    if (current == null) return -1;
    return _playbackOrderIds().indexOf(_queueKey(current));
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
  List<Music> get musicOnlyList =>
      _musicList.where((music) => !_isVideoTrack(music)).toList();
  List<Music> get videoMusicList =>
      _musicList.where((music) => _isVideoTrack(music)).toList();
  List<Music> get earlyListenedMusicList =>
      List.unmodifiable(_cachedEarlyListened);
  List<Music> get recentlyAddedMusicList {
    final items = List<Music>.from(_musicList)
      ..sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    return items.take(24).toList(growable: false);
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

    final favoriteGenres = <String, int>{};
    final favoriteArtists = <String, int>{};
    final favoriteYears = <String, int>{};
    for (final music in _musicList) {
      if (!music.isFavorite) continue;
      final genre = music.genre.trim().toLowerCase();
      final artist = music.artist.trim().toLowerCase();
      final year = music.year.trim();
      if (genre.isNotEmpty && genre != 'unknown') {
        favoriteGenres[genre] = (favoriteGenres[genre] ?? 0) + 1;
      }
      if (artist.isNotEmpty && artist != 'unknown artist') {
        favoriteArtists[artist] = (favoriteArtists[artist] ?? 0) + 1;
      }
      if (_normalizedYear(year).isNotEmpty) {
        favoriteYears[_normalizedYear(year)] =
            (favoriteYears[_normalizedYear(year)] ?? 0) + 1;
      }
    }

    final now = DateTime.now();
    final scored = _musicList.map((music) {
      final genre = music.genre.trim().toLowerCase();
      final artist = music.artist.trim().toLowerCase();
      final year = _normalizedYear(music.year);
      final ageDays = now.difference(music.dateAdded).inDays.clamp(0, 365);
      final lastPlayedDays = music.lastPlayed == null
          ? 365
          : now.difference(music.lastPlayed!).inDays.clamp(0, 365);

      var score = 0.0;
      if (music.isFavorite) score += 80;
      score += (favoriteGenres[genre] ?? 0) * 16;
      score += (favoriteArtists[artist] ?? 0) * 13;
      score += (favoriteYears[year] ?? 0) * 7;
      score += music.playCount.clamp(0, 25) * 3;
      score += (365 - ageDays) / 365 * 10;
      score += (365 - lastPlayedDays) / 365 * 8;
      if (_isVideoTrack(music)) score += 2;
      score += _recommendationJitter(music);

      return _RecommendedTrack(music, score);
    }).toList()
      ..sort((a, b) {
        final scoreCompare = b.score.compareTo(a.score);
        if (scoreCompare != 0) return scoreCompare;
        return b.music.dateAdded.compareTo(a.music.dateAdded);
      });

    final result = scored.map((item) => item.music).take(24).toList(growable: false);
    _cachedRecommended = result;
    _recommendedVersion = _dataVersion;
    return result;
  }

  List<LibraryMiniStat> get libraryMiniStats {
    final dashboard = libraryStatsDashboard;
    return [
      LibraryMiniStat('Total records', '${dashboard.totalRecords}', 1),
      LibraryMiniStat('Liked records', '${dashboard.likedRecords}',
          _ratio(dashboard.likedRecords, dashboard.totalRecords)),
      LibraryMiniStat('Played records', '${dashboard.playedRecords}',
          _ratio(dashboard.playedRecords, dashboard.totalRecords)),
      LibraryMiniStat('Videos', '${dashboard.videoRecords}',
          _ratio(dashboard.videoRecords, dashboard.totalRecords)),
      LibraryMiniStat('Genres', '${dashboard.genreCount}',
          _ratio(dashboard.genreCount, dashboard.totalRecords)),
      LibraryMiniStat('Artists', '${dashboard.artistCount}',
          _ratio(dashboard.artistCount, dashboard.totalRecords)),
      LibraryMiniStat('Albums', '${dashboard.albumCount}',
          _ratio(dashboard.albumCount, dashboard.totalRecords)),
      LibraryMiniStat('Years', '${dashboard.yearCount}',
          _ratio(dashboard.yearCount, dashboard.totalRecords)),
      LibraryMiniStat('Total plays', '${dashboard.totalPlays}',
          min(dashboard.totalPlays / 100, 1).toDouble()),
      LibraryMiniStat('AI candidates', '${dashboard.aiCandidates}',
          _ratio(dashboard.aiCandidates, 24)),
      LibraryMiniStat(
          'Top genre', dashboard.topGenre.label, dashboard.topGenre.ratio),
      LibraryMiniStat(
          'Top artist', dashboard.topArtist.label, dashboard.topArtist.ratio),
    ];
  }

  LibraryStatsDashboard get libraryStatsDashboard {
    if (_cachedStats != null && _statsVersion == _dataVersion) {
      return _cachedStats!;
    }
    final total = _musicList.length;
    final liked = favoriteMusicList.length;
    final videoCount = videoMusicList.length;
    final musicCount = total - videoCount;
    final genres = _normalizedUniqueCount(_musicList.map((m) => m.genre));
    final artists = _normalizedUniqueCount(_musicList.map((m) => m.artist));
    final albums = _normalizedUniqueCount(_musicList.map((m) => m.album));
    final years = _normalizedUniqueCount(_musicList.map((m) => m.year));
    final played = _musicList.where((music) => music.lastPlayed != null).length;
    final totalPlays =
        _musicList.fold<int>(0, (sum, music) => sum + music.playCount);
    final recommended = recommendedMusicList.length;
    final totalDuration = _musicList.fold<Duration>(
      Duration.zero,
      (sum, music) => sum + (music.duration ?? Duration.zero),
    );
    final topPlayedTracks = List<Music>.from(_musicList)
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    final recentlyPlayed = _musicList
        .where((music) => music.lastPlayed != null)
        .toList()
      ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));

    final result = LibraryStatsDashboard(
      totalRecords: total,
      musicRecords: musicCount,
      videoRecords: videoCount,
      likedRecords: liked,
      playedRecords: played,
      playlistCount: _playlists.length,
      totalPlays: totalPlays,
      totalDuration: totalDuration,
      genreCount: genres,
      artistCount: artists,
      albumCount: albums,
      yearCount: years,
      aiCandidates: recommended,
      topGenre: _topRankItem(_musicList.map((m) => m.genre), 'No genre'),
      topArtist: _topRankItem(_musicList.map((m) => m.artist), 'No artist'),
      mediaSlices: [
        StatsSlice('Music', musicCount),
        StatsSlice('Videos', videoCount),
      ],
      likedSlices: [
        StatsSlice('Liked', liked),
        StatsSlice('Not liked', max(0, total - liked)),
      ],
      playedSlices: [
        StatsSlice('Played', played),
        StatsSlice('Unplayed', max(0, total - played)),
      ],
      genreRanks: _rankStrings(_musicList.map((m) => m.genre), top: 8),
      artistRanks: _rankStrings(_musicList.map((m) => m.artist), top: 8),
      albumRanks: _rankStrings(_musicList.map((m) => m.album), top: 8),
      yearRanks: _rankStrings(
        _musicList.map((m) {
          final year = _normalizedYear(m.year);
          return year.isEmpty ? 'Unknown' : year;
        }),
        top: 8,
      ),
      playlistRanks: _playlistRanks(total),
      topPlayedTracks: topPlayedTracks
          .where((music) => music.playCount > 0)
          .take(8)
          .map((music) => StatsRankItem(
                music.title,
                music.playCount,
                _ratio(music.playCount, max(1, totalPlays)),
                subtitle: music.artist,
              ))
          .toList(),
      recentlyPlayed: recentlyPlayed
          .take(8)
          .map((music) => StatsRankItem(
                music.title,
                music.playCount,
                _ratio(music.playCount, max(1, totalPlays)),
                subtitle: music.artist,
              ))
          .toList(),
      earlyListened: _cachedEarlyListened
          .take(8)
          .map((music) => StatsRankItem(
                music.title,
                music.playCount,
                _ratio(music.playCount, max(1, totalPlays)),
                subtitle: music.artist,
              ))
          .toList(),
      recommendationSignals: _recommendationSignalStats(),
    );
    _cachedStats = result;
    _statsVersion = _dataVersion;
    return result;
  }

  List<Playlist> get systemPlaylists => const [];
  List<Playlist> get allPlaylists => List.unmodifiable(_playlists);

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
    _scheduleUpdate(delay: const Duration(milliseconds: 35));
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

  Future<void> setSafeEarsEnabled(bool value) async {
    _safeEarsEnabled = value;
    notifyListeners();
    if (value && _volume > _safeEarsMaxVolume) {
      setVolume(_safeEarsMaxVolume);
    } else {
      await _setOutputVolume(_volume);
      await _audioHandler.setVolumeFromService(
        _effectiveBackendVolume(_volume) / 100.0,
      );
    }
    await _saveAudioEffectsSettings();
  }

  Future<void> setSafeEarsMaxVolume(double value) async {
    _safeEarsMaxVolume = value.clamp(35.0, 100.0).toDouble();
    notifyListeners();
    if (_safeEarsEnabled && _volume > _safeEarsMaxVolume) {
      setVolume(_safeEarsMaxVolume);
    } else {
      await _setOutputVolume(_volume);
      await _audioHandler.setVolumeFromService(
        _effectiveBackendVolume(_volume) / 100.0,
      );
    }
    await _saveAudioEffectsSettings();
  }

  void setDspEnabled(bool value) {
    _dspEnabled = value;
    _scheduleUpdate(delay: const Duration(milliseconds: 35));
    notifyListeners();
    _saveDebounced();
  }

  void setDspLoudnessNormalizationEnabled(bool value) {
    _dspLoudnessNormalizationEnabled = value;
    if (value) _dspEnabled = true;
    _scheduleUpdate(delay: const Duration(milliseconds: 35));
    notifyListeners();
    _saveDebounced();
  }

  void setDspLimiterEnabled(bool value) {
    _dspLimiterEnabled = value;
    if (value) _dspEnabled = true;
    _scheduleUpdate(delay: const Duration(milliseconds: 35));
    notifyListeners();
    _saveDebounced();
  }

  void setDspCompressorEnabled(bool value) {
    _dspCompressorEnabled = value;
    if (value) _dspEnabled = true;
    _scheduleUpdate(delay: const Duration(milliseconds: 35));
    notifyListeners();
    _saveDebounced();
  }

  void setDspTone({
    double? bass,
    double? mid,
    double? treble,
  }) {
    _dspBass = (bass ?? _dspBass).clamp(-6.0, 6.0).toDouble();
    _dspMid = (mid ?? _dspMid).clamp(-6.0, 6.0).toDouble();
    _dspTreble = (treble ?? _dspTreble).clamp(-6.0, 6.0).toDouble();
    if (_dspBass.abs() > 0.05 ||
        _dspMid.abs() > 0.05 ||
        _dspTreble.abs() > 0.05) {
      _dspEnabled = true;
    }
    _scheduleUpdate(delay: const Duration(milliseconds: 45));
    notifyListeners();
    _saveDebounced();
  }

  void resetDspTone() {
    _dspBass = 0.0;
    _dspMid = 0.0;
    _dspTreble = 0.0;
    _scheduleUpdate(delay: const Duration(milliseconds: 35));
    notifyListeners();
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
    _scheduleUpdate(delay: const Duration(milliseconds: 35));
  }

  double _normalizeEqGain(double value) =>
      double.parse(value.clamp(-12.0, 12.0).toStringAsFixed(1));

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
    _scheduleUpdate(delay: const Duration(milliseconds: 35));
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

    if (!_usingNativeWindowsAudio &&
        _videoPlayback.hasVideoTrack &&
        identical(player, _mediaPlayer)) {
      _effectsVolumeFactor = 1.0;
      await _setPlayerVolumeInternal(player, _volume);
      return;
    }

    final native = player.platform;
    final canUseNativeAudioFilter =
        native is NativePlayer && _supportsNativeAudioFilters;
    final filter = canUseNativeAudioFilter ? _buildAudioFilter() : '';

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
    if (canUseNativeAudioFilter) {
      await _setNativeAudioFilter(native, filter);
    } else if (native is NativePlayer && _lastNativeAudioFilterKey != '') {
      await _setNativeAudioFilter(native, '');
    }
    if (generation != null && generation != _effectsUpdateGeneration) return;

    final nextVolumeFactor = canUseNativeAudioFilter
        ? _buildNativeFilterVolumeFactor()
        : _buildFallbackEqVolumeFactor();
    final shouldForceVolumeRefresh =
        _safeEarsEnabled || canUseNativeAudioFilter || _isEffectsEnabled;
    if (shouldForceVolumeRefresh ||
        (nextVolumeFactor - _effectsVolumeFactor).abs() > 0.005) {
      _effectsVolumeFactor = nextVolumeFactor;
      await _setPlayerVolumeInternal(player, _volume);
      _logPcEqVolumeFactorIfNeeded(nextVolumeFactor);
    }
  }

  bool get _supportsNativeAudioFilters {
    if (kIsWeb) return false;

    if (Platform.isWindows || Platform.isLinux) return false;
    return true;
  }

  String _buildAudioFilter() {
    final parts = <String>[];
    if (_dspEnabled && _dspLoudnessNormalizationEnabled) {
      parts.add('dynaudnorm=f=250:g=7:p=0.86:m=8:r=0.9');
    }
    final eqValues = _isEffectsEnabled && _isEqualizerEnabled
        ? currentEqBandValues
        : _eqPresets['Flat']!;
    if (_isEffectsEnabled && _isEqualizerEnabled) {
      parts.add('volume=${_buildEqHeadroomDb(eqValues).toStringAsFixed(1)}dB');
    }
    parts.addAll(_buildEqualizerFilterParts(eqValues));
    parts.addAll(_buildDspToneFilterParts());

    if (_dspEnabled && _dspCompressorEnabled) {
      parts.add(
          'acompressor=threshold=0.22:ratio=1.8:attack=18:release=260:makeup=1.0:knee=2.5');
    }

    if (_isEffectsEnabled && _reverb > 0) {
      parts.add(
          'aecho=0.8:0.88:${(_reverb * 60).toInt() + 20}:${_reverb * 0.3}');
      parts.add(
          'freeverb=roomsize=${0.7 + (_reverb * 0.25)}:damp=${0.2 + (1.0 - _reverb) * 0.5}:wet=${_reverb * 0.8}:dry=${1.0 - (_reverb * 0.5)}:width=1.0');
      parts.add('extrastereo=m=${1.0 + _reverb * 1.5}');
    }

    if (_dspEnabled && _dspLimiterEnabled) {
      parts.add('alimiter=limit=0.89:level=disabled:attack=5:release=100');
    }

    return parts.join(',');
  }

  List<String> _buildEqualizerFilterParts(List<double> values) {
    return List.generate(_eqFreqs.length, (index) {
      final value = values[index].clamp(-12.0, 12.0);
      final gain = value.toStringAsFixed(1);
      return 'equalizer=f=${_eqFreqs[index]}:width_type=o:width=1.05:g=$gain';
    });
  }

  List<String> _buildDspToneFilterParts() {
    if (!_dspEnabled) return const [];
    final filters = <String>[];
    if (_dspBass.abs() > 0.05) {
      filters.add(
          'equalizer=f=95:width_type=o:width=1.15:g=${_dspBass.toStringAsFixed(1)}');
    }
    if (_dspMid.abs() > 0.05) {
      filters.add(
          'equalizer=f=1000:width_type=o:width=1.05:g=${_dspMid.toStringAsFixed(1)}');
    }
    if (_dspTreble.abs() > 0.05) {
      filters.add(
          'equalizer=f=8500:width_type=o:width=1.1:g=${_dspTreble.toStringAsFixed(1)}');
    }
    return filters;
  }

  double _buildEqHeadroomDb(List<double> values) {
    final strongestBoost =
        values.fold<double>(0.0, (maxValue, value) => max(maxValue, value));
    final positiveAverage = values
            .where((value) => value > 0)
            .fold<double>(0.0, (total, value) => total + value) /
        values.length;
    return -(strongestBoost * 0.32 + positiveAverage * 0.28)
        .clamp(0.0, 7.0)
        .toDouble();
  }

  double _buildNativeFilterVolumeFactor() {
    if (!_isEffectsEnabled || !_isEqualizerEnabled) {
      return _safeEarsVolumeFactor();
    }
    final values = currentEqBandValues;
    final strongestBoost =
        values.fold<double>(0.0, (maxValue, value) => max(maxValue, value));
    final positiveAverage = values
            .where((value) => value > 0)
            .fold<double>(0.0, (total, value) => total + value) /
        values.length;
    final attenuationDb = -(strongestBoost * 0.16 + positiveAverage * 0.14)
        .clamp(0.0, 3.5)
        .toDouble();
    final headroom = pow(10, attenuationDb / 20).clamp(0.67, 1.0).toDouble();
    return (headroom * _buildDspHeadroomFactor() * _safeEarsVolumeFactor())
        .clamp(0.22, 1.0)
        .toDouble();
  }

  double _buildFallbackEqVolumeFactor() {
    final dspFactor = _buildFallbackDspVolumeFactor();
    if (!_isEffectsEnabled || !_isEqualizerEnabled) {
      return (dspFactor * _safeEarsVolumeFactor()).clamp(0.2, 1.15).toDouble();
    }
    final values = currentEqBandValues;
    final averageGain =
        values.fold<double>(0.0, (total, value) => total + value) /
            values.length;
    final bassAverage = values.take(3).fold<double>(0.0, (a, b) => a + b) / 3;
    final trebleAverage = values.skip(6).fold<double>(0.0, (a, b) => a + b) / 4;
    final midAverage =
        values.skip(3).take(3).fold<double>(0.0, (a, b) => a + b) / 3;
    final strongestBoost =
        values.fold<double>(0.0, (maxValue, value) => max(maxValue, value));
    final strongestCut =
        values.fold<double>(0.0, (minValue, value) => min(minValue, value));
    final db = (averageGain * 0.8 +
            bassAverage * 0.35 +
            midAverage * 0.25 +
            trebleAverage * 0.25 +
            strongestBoost * 0.18 +
            strongestCut * 0.12)
        .clamp(-12.0, 9.0);
    final colorFactor = pow(10, db / 20).clamp(0.45, 1.35).toDouble();
    return (colorFactor * dspFactor * _safeEarsVolumeFactor())
        .clamp(0.2, 1.35)
        .toDouble();
  }

  double _buildFallbackDspVolumeFactor() {
    if (!_dspEnabled) return 1.0;
    var db = 0.0;
    if (_dspLoudnessNormalizationEnabled) db += 0.7;
    if (_dspCompressorEnabled) db -= 0.3;
    db += _dspBass * 0.10 + _dspMid * 0.06 + _dspTreble * 0.06;
    if (_dspLimiterEnabled) {
      db -= 0.45;
      db -= max(0.0, db - 0.6) * 0.95;
    }
    return pow(10, db.clamp(-5.0, 1.2) / 20).clamp(0.5, 1.06).toDouble();
  }

  double _buildDspHeadroomFactor() {
    if (!_dspEnabled) return 1.0;
    final boostDb = max(0.0, _dspBass) * 0.12 +
        max(0.0, _dspMid) * 0.08 +
        max(0.0, _dspTreble) * 0.08 +
        (_dspCompressorEnabled ? 0.4 : 0.0);
    final limiterHeadroom = _dspLimiterEnabled ? 0.6 : 0.0;
    final attenuationDb = -(boostDb + limiterHeadroom).clamp(0.0, 3.5);
    return pow(10, attenuationDb / 20).clamp(0.66, 1.0).toDouble();
  }

  double _safeEarsVolumeFactor() {
    if (!_safeEarsEnabled || _volume <= 0) return 1.0;
    final safeVolume = _safeEarsMaxVolume.clamp(35.0, 100.0).toDouble();
    return (safeVolume / _volume).clamp(0.0, 1.0).toDouble();
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
    await _audioHandler.setSpeedFromService(_isEffectsEnabled ? _speed : 1.0);
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
    final recreateVideoController = _videoDecoderMode != video;
    _audioDecoderMode = audio;
    _videoDecoderMode = video;
    await _applyDecoderSettings(_mediaPlayer);
    if (recreateVideoController && _videoPlayback.hasVideoTrack) {
      final track = currentMusic;
      if (track != null) {
        _videoPlayback.reset();
        _videoPlayback.setCurrentTrack(track);
      }
    }
    await _ensureVideoControllerForCurrentTrack();
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
    await _videoPlayback.applyDecoderSettings(
      player,
      audioDecoderThreadValue: _audioDecoderThreadValue(),
      linuxAudioOutputDrivers: _linuxAudioOutputDrivers(),
    );
  }

  String _audioDecoderThreadValue() {
    switch (_audioDecoderMode) {
      case DecoderMode.software:
        return '1';
      case DecoderMode.hardware:
      case DecoderMode.auto:
        return '0';
    }
  }

  String _linuxAudioOutputDrivers() {
    final configured = Platform.environment['PLAYER_VF_LINUX_AUDIO_OUTPUTS'];
    if (configured != null && configured.trim().isNotEmpty) {
      return configured.trim();
    }
    return 'pulse,pipewire,alsa';
  }

  Future<void> loadSubtitleFile(String path) async {
    await _videoPlayback.loadSubtitleFile(path);
  }

  Future<void> loadSubtitleUrl(String url, {String? title}) async {
    await _videoPlayback.loadSubtitleUrl(url, title: title);
  }

  Future<void> disableSubtitles() async {
    await _videoPlayback.disableSubtitles();
  }

  Future<void> _applySidecarSubtitleIfAvailable(
      Player player, String mediaPath) async {
    await _videoPlayback.applySidecarSubtitleIfAvailable(player, mediaPath);
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
    await _keepOriginalLyricsTimingForMusic(music, rawLyrics);
    await file.writeAsString(rawLyrics);
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    return LyricsDocument.parse(rawLyrics, source: path);
  }

  Future<void> keepOriginalLyricsTimingForCurrent(String rawLyrics) async {
    final music = currentMusic;
    if (music == null || kIsWeb) return;
    final expectedLyricsKey = _lyricsOwnerKey(music);
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return;
    await _keepOriginalLyricsTimingForMusic(music, rawLyrics);
  }

  Future<LyricsDocument?> restoreOriginalLyricsTimingForCurrent() async {
    final music = currentMusic;
    if (music == null || kIsWeb) return null;
    final expectedLyricsKey = _lyricsOwnerKey(music);
    final backupPath = await _manualLyricsTimingBackupPathForMusic(music);
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) return null;
    final raw = await backupFile.readAsString();
    if (!_isCurrentLyricsOwner(expectedLyricsKey)) return null;
    return saveLyricsForCurrent(raw);
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
    final dir = await getPlayerVfDocumentsDirectory();
    final fileName = '${_safeLyricsFileToken(music)}.lrc';
    return p.join(dir.path, 'lyrics', fileName);
  }

  Future<String> _manualPlainLyricsPathForMusic(Music music) async {
    final dir = await getPlayerVfDocumentsDirectory();
    final fileName = '${_safeLyricsFileToken(music)}.txt';
    return p.join(dir.path, 'lyrics', fileName);
  }

  Future<String> _manualLyricsTimingBackupPathForMusic(Music music) async {
    final dir = await getPlayerVfDocumentsDirectory();
    final fileName = '${_safeLyricsFileToken(music)}.original.lrc';
    return p.join(dir.path, 'lyrics', fileName);
  }

  Future<void> _keepOriginalLyricsTimingForMusic(
    Music music,
    String rawLyrics, {
    bool overwrite = false,
  }) async {
    if (rawLyrics.trim().isEmpty) return;
    final file = File(await _manualLyricsTimingBackupPathForMusic(music));
    if (!overwrite && await file.exists()) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(rawLyrics);
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
      await _keepOriginalLyricsTimingForMusic(
        music,
        synced,
        overwrite: true,
      );
      final path = await _manualLyricsPathForMusic(music);
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString(synced);
      preferredPath = path;
      preferredRaw = synced;
    }

    if (plain != null && plain.isNotEmpty) {
      if (synced == null || synced.isEmpty) {
        await _keepOriginalLyricsTimingForMusic(
          music,
          plain,
          overwrite: true,
        );
      }
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
    final appDir = await getPlayerVfDocumentsDirectory();
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
    final maxVolume =
        _safeEarsEnabled ? _safeEarsMaxVolume.clamp(35.0, 100.0) : 100.0;
    return (value * _effectsVolumeFactor).clamp(0.0, maxVolume).toDouble();
  }

  bool _shouldUseNativeWindowsAudio(Music track) {
    if (kIsWeb || _isVideoTrack(track)) return false;

    final rawPath = track.filePath.trim();
    if (rawPath.isEmpty || rawPath.startsWith('blob:')) return false;

    if (Platform.isAndroid) return true;
    if (Platform.isWindows) return false;
    return false;
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
    _startSongGapCountdown(generation, gap);
    await Future<void>.delayed(gap);
    if (generation != _audioTransitionGeneration) return;
    _clearSongGapCountdown();
  }

  void _startSongGapCountdown(int generation, Duration gap) {
    _songGapCountdownTimer?.cancel();
    final startedAt = DateTime.now();
    _songGapRemainingNotifier.value = gap;
    _updateSnapshot();
    notifyListeners();
    _songGapCountdownTimer =
        Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (generation != _audioTransitionGeneration) {
        _clearSongGapCountdown();
        return;
      }
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = gap - elapsed;
      _songGapRemainingNotifier.value =
          remaining > Duration.zero ? remaining : Duration.zero;
      _updateSnapshot();
      if (remaining <= Duration.zero) {
        _clearSongGapCountdown();
      }
    });
  }

  void _clearSongGapCountdown() {
    _songGapCountdownTimer?.cancel();
    _songGapCountdownTimer = null;
    if (_songGapRemainingNotifier.value != Duration.zero) {
      _songGapRemainingNotifier.value = Duration.zero;
      _updateSnapshot();
      notifyListeners();
    }
  }

  Future<void> _setPlayerVolumeInternal(Player player, double value) async {
    await _setPlayerVolume(player, value);
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

    await _setOutputVolume(value);
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
      final value = from + ((to - from) * eased);
      if (player == null) {
        await _setBackendVolume(value, internal: true);
      } else {
        await _setPlayerVolumeInternal(targetPlayer, value);
      }
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
    if (generation == _audioTransitionGeneration) {
      if (player == null) {
        await _setBackendVolume(to, internal: true);
      } else {
        await _setPlayerVolumeInternal(targetPlayer, to);
      }
    }
  }

  Future<void> _smoothOpenAndPlay(
    Music track,
    Duration startPosition, {
    bool playAfterOpen = true,
  }) async {
    final trackIsVideo = _isVideoTrack(track);
    _playbackDebug(
      '_smoothOpenAndPlay title="${track.title}" start=${startPosition.inMilliseconds}ms playAfterOpen=$playAfterOpen isVideo=$trackIsVideo',
    );
    final generation = ++_audioTransitionGeneration;
    _lastTrackOpenStartedAt = DateTime.now();
    _clearSongGapCountdown();
    final trackKey = _queueKey(track);
    final targetVolume = _volume.clamp(0.0, 100.0);
    final currentPlayer = _mediaPlayer;
    final useNativeWindowsAudio = _shouldUseNativeWindowsAudio(track);
    final isSwitchingTracks = _openedMusicId != null &&
        _openedMusicId != trackKey &&
        startPosition <= Duration.zero;
    final shouldGapBetweenTracks = isSwitchingTracks &&
        _songGapDuration > Duration.zero &&
        startPosition <= Duration.zero;
    final canCrossfade = _isPlaying &&
        playAfterOpen &&
        !shouldGapBetweenTracks &&
        !_usingNativeWindowsAudio &&
        !useNativeWindowsAudio &&
        !_videoPlayback.hasVideoTrack &&
        !trackIsVideo;
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
          );
        }

        final shouldResumeAfterGap =
            playAfterOpen || _isPlaying || shouldGapBetweenTracks;
        if (_isPlaying) await _pauseCurrentBackend();
        await _waitForSongGapIfNeeded(generation, shouldGapBetweenTracks);
        if (generation != _audioTransitionGeneration) return;
        await _openTrackMedia(track);
        _playbackDebug(
            '_smoothOpenAndPlay opened track generation=$generation');

        if (startPosition > Duration.zero) {
          await _seekCurrentBackend(startPosition);
          _position = startPosition;
          _positionNotifier.value = startPosition;
        }

        if (_shouldResumeCurrentTrack) {
          await _applyResumePositionIfNeeded(trackKey);
        }

        _suppressPositionUpdatesForTrackChange = false;
        if (trackIsVideo) {
          if (shouldResumeAfterGap) {
            _playbackDebug(
                '_smoothOpenAndPlay calling _playCurrentBackend generation=$generation');
            await _playCurrentBackend();
            _queueVideoVolumeRefresh(targetVolume);
          }
          return;
        }
        if (targetVolume > 0) {
          await _setBackendVolume(0, internal: true);
        }
        if (shouldResumeAfterGap) {
          _playbackDebug(
              '_smoothOpenAndPlay calling _playCurrentBackend generation=$generation');
          await _playCurrentBackend();
        }
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

    final incomingPlayer = _createPlayer();
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
        await _applyResumePositionOnPlayerIfNeeded(incomingPlayer, trackKey);
      }

      if (playAfterOpen) {
        await incomingPlayer.play();
        _syncExternalPlaybackState(playing: true, position: _position);
      }

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
    if (_usingNativeWindowsAudio ||
        _usingLinuxExternalPlayback ||
        _videoPlayback.hasVideoTrack) {
      await _playCurrentBackend();
      if (_videoPlayback.hasVideoTrack) {
        _queueVideoVolumeRefresh(_volume.clamp(0.0, 100.0));
      }
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
    if (_usingNativeWindowsAudio ||
        _usingLinuxExternalPlayback ||
        _videoPlayback.hasVideoTrack) {
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
      unawaited(_audioHandler.setWindowsMediaControlsActive(state));
      _syncWindowsMediaControlOwnership();
      _syncExternalPlaybackState(playing: state);
      return;
    }
    _isPlaying = state;
    _playingNotifier.value = state;
    _updateSnapshot();
    unawaited(_audioHandler.setWindowsMediaControlsActive(state));
    _syncWindowsMediaControlOwnership();
    _syncExternalPlaybackState(playing: state);
    _savePlaybackDebounced();
    notifyListeners();
  }

  void _updateSnapshot() {
    _snapshotNotifier.value = PlaybackSnapshot(
      position: _position,
      duration: _duration,
      songGapRemaining: _songGapRemainingNotifier.value,
      isPlaying: _isPlaying,
      volume: _volume,
    );
  }

  Future<void> _preparePlayerForTrack(
    Player player,
    Music track, {
    required double volume,
  }) async {
    _completedTrackId = null;
    _videoPlayback.setCurrentTrack(track);
    await _audioHandler.updateNowPlaying(
      track,
      playing: _isPlaying,
      position: _position,
      duration: track.duration,
    );
    _lastNativeAudioFilterKey = null;
    await _videoPlayback.prepareForTrack(
      player,
      track,
      volume: volume,
      extras: _mediaExtras(track),
      setVolume: _setPlayerVolume,
      applyAudioEffects: _applyAudioEffects,
      audioDecoderThreadValue: _audioDecoderThreadValue(),
      linuxAudioOutputDrivers: _linuxAudioOutputDrivers(),
    );
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
    _playbackDebug(
      '_openTrackMedia title="${track.title}" path="${track.filePath}" video=${_isVideoTrack(track)}',
    );
    _videoPlayback.setCurrentTrack(track);
    _completedTrackId = null;
    _lastNativeAudioFilterKey = null;
    final wasUsingNativeAudio = _usingNativeWindowsAudio;
    final useNativeWindowsAudio = _shouldUseNativeWindowsAudio(track);
    _usingNativeWindowsAudio = useNativeWindowsAudio;
    if (useNativeWindowsAudio) {
      try {
        await _mediaPlayer.stop();
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
        debugPrint('Native audio failed, falling back to media_kit: $e');
        _usingNativeWindowsAudio = false;
        await _audioHandler.stop();
      }
    } else if (wasUsingNativeAudio) {
      await _audioHandler.stop();
    }

    await _audioHandler.updateNowPlaying(
      track,
      playing: false,
      position: _position,
      duration: track.duration,
    );
    await _applyDecoderSettings(_mediaPlayer);
    if (_isVideoTrack(track)) {
      await _videoPlayback.openVideoTrack(
        player: _mediaPlayer,
        track: track,
        extras: _mediaExtras(track),
        audioDecoderThreadValue: _audioDecoderThreadValue(),
        linuxAudioOutputDrivers: _linuxAudioOutputDrivers(),
      );
      _playbackDebug('_openTrackMedia open success');
      _audioHandler.setExternalPlaybackState(
        playing: false,
        position: _position,
        duration: _duration,
      );
      return;
    }
    await _serializeMediaOpen(
      () => _openMediaKitPath(
        _mediaPlayer,
        track,
        play: false,
      ),
    );
    _playbackDebug('_openTrackMedia open success');
    await _applySidecarSubtitleIfAvailable(_mediaPlayer, track.filePath);
    await _setOutputVolume(_volume);
    await _scheduleUpdateNow();
    _audioHandler.setExternalPlaybackState(
      playing: false,
      position: _position,
      duration: _duration,
    );
  }

  void _queueVideoVolumeRefresh(double value) {
    unawaited(_setOutputVolume(value).catchError((Object error) {
      _playbackDebug('video volume refresh failed: $error');
    }));
  }

  Future<void> _openMediaKitPath(
    Player player,
    Music track, {
    required bool play,
  }) async {
    await _videoPlayback.openMediaKitPath(
      player,
      track,
      extras: _mediaExtras(track),
      play: play,
    );
  }

  Future<void> _serializeMediaOpen(Future<void> Function() action) {
    final next = _mediaOpenQueue.then((_) => action());
    _mediaOpenQueue = next.catchError((_) {});
    return next;
  }

  Future<void> _openLinuxExternalVideo(
    Music track, {
    Duration startPosition = Duration.zero,
  }) async {
    if (!Platform.isLinux) return;

    await _pauseCurrentBackend();
    _videoPlayback.setCurrentTrack(track);
    _duration = track.duration ?? _duration;
    _durationNotifier.value = _duration;
    _position = startPosition;
    _positionNotifier.value = startPosition;

    final target = track.filePath.trim();
    if (target.isEmpty) {
      throw StateError('Video path is empty.');
    }

    final commands = _linuxVideoPlayerCommands(
      target,
      startPosition: startPosition,
      httpHeaders: track.httpHeaders,
    );

    Object? lastError;
    for (final command in commands) {
      try {
        final process = await Process.start(
          command.first,
          command.sublist(1),
        );
        _attachLinuxExternalProcess(process);
        _startLinuxExternalProgress(track);
        debugPrint('Opened Linux video externally with ${command.first}.');
        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError(
      'Could not open video on Linux. Bundle mpv with tool/package_linux_mpv.sh, or install mpv/vlc. Last error: $lastError',
    );
  }

  Future<void> _tryOpenLinuxExternalAudioAfterFailure(Object failure) async {
    if (kIsWeb || !Platform.isLinux) return;

    final track = _streamingMusic ?? currentMusic;
    if (track == null || _isVideoTrack(track)) return;

    try {
      await _openLinuxExternalAudio(track, startPosition: _position);
    } catch (fallbackError) {
      debugPrint(
          'Linux external audio fallback failed after media_kit error: $failure; fallback: $fallbackError');
    }
  }

  Future<void> _tryOpenLinuxExternalVideoAfterFailure(
    Music track,
    Object failure, {
    Duration startPosition = Duration.zero,
  }) async {
    if (kIsWeb || !Platform.isLinux || !_isVideoTrack(track)) return;

    try {
      await _openLinuxExternalVideo(track, startPosition: startPosition);
      final trackKey = _queueKey(track);
      _openedMusicId = trackKey;
      _resumeTrackId = trackKey;
      _resumePosition = startPosition;
      _shouldResumeCurrentTrack = startPosition > Duration.zero;
      notifyListeners();
    } catch (fallbackError) {
      debugPrint(
          'Linux external video fallback failed after media_kit error: $failure; fallback: $fallbackError');
    }
  }

  Future<void> _openLinuxExternalAudio(
    Music track, {
    Duration startPosition = Duration.zero,
  }) async {
    if (kIsWeb || !Platform.isLinux) return;

    await _pauseCurrentBackend();
    _videoPlayback.reset();
    _duration = track.duration ?? _duration;
    _durationNotifier.value = _duration;
    _position = startPosition;
    _positionNotifier.value = startPosition;

    final target = track.filePath.trim();
    if (target.isEmpty) {
      throw StateError('Audio path is empty.');
    }

    final commands = _linuxAudioPlayerCommands(
      target,
      startPosition: startPosition,
      httpHeaders: track.httpHeaders,
    );

    Object? lastError;
    for (final command in commands) {
      try {
        final process = await Process.start(
          command.first,
          command.sublist(1),
        );
        _attachLinuxExternalProcess(process);
        _startLinuxExternalProgress(track);
        debugPrint('Opened Linux audio externally with ${command.first}.');
        return;
      } catch (error) {
        lastError = error;
      }
    }

    throw StateError(
      'Could not open audio on Linux. Bundle mpv with tool/package_linux_mpv.sh, or install mpv/vlc. Last error: $lastError',
    );
  }

  List<List<String>> _linuxVideoPlayerCommands(
    String target, {
    required Duration startPosition,
    Map<String, String> httpHeaders = const {},
  }) {
    final mpvArgs = [
      '--force-window=yes',
      '--ao=${_linuxAudioOutputDrivers()}',
      ..._linuxMpvHttpHeaderArgs(httpHeaders),
      if (startPosition > Duration.zero) '--start=${startPosition.inSeconds}',
      target,
    ];
    final vlcArgs = [
      if (startPosition > Duration.zero)
        '--start-time=${startPosition.inSeconds}',
      target,
    ];

    final commands = <List<String>>[];
    for (final mpv in _bundledLinuxMpvCandidates()) {
      commands.add([mpv, ...mpvArgs]);
    }
    commands.addAll([
      ['mpv', ...mpvArgs],
      ['vlc', ...vlcArgs],
      ['xdg-open', target],
    ]);
    return commands;
  }

  List<List<String>> _linuxAudioPlayerCommands(
    String target, {
    required Duration startPosition,
    Map<String, String> httpHeaders = const {},
  }) {
    final mpvArgs = [
      '--no-video',
      '--ao=${_linuxAudioOutputDrivers()}',
      ..._linuxMpvHttpHeaderArgs(httpHeaders),
      if (startPosition > Duration.zero) '--start=${startPosition.inSeconds}',
      target,
    ];
    final vlcArgs = [
      '--intf',
      'dummy',
      if (startPosition > Duration.zero)
        '--start-time=${startPosition.inSeconds}',
      target,
    ];

    final commands = <List<String>>[];
    for (final mpv in _bundledLinuxMpvCandidates()) {
      commands.add([mpv, ...mpvArgs]);
    }
    commands.addAll([
      ['mpv', ...mpvArgs],
      ['vlc', ...vlcArgs],
      ['xdg-open', target],
    ]);
    return commands;
  }

  List<String> _linuxMpvHttpHeaderArgs(Map<String, String> headers) {
    if (headers.isEmpty) return const [];

    final args = <String>[];
    final genericHeaders = <String>[];
    for (final entry in headers.entries) {
      final key = entry.key.trim();
      final value = entry.value.trim();
      if (key.isEmpty || value.isEmpty) continue;

      final lowerKey = key.toLowerCase();
      if (lowerKey == 'user-agent') {
        args.add('--user-agent=$value');
      } else if (lowerKey == 'referer' || lowerKey == 'referrer') {
        args.add('--referrer=$value');
      } else {
        genericHeaders.add(
            '${key.replaceAll(',', r'\,')}: ${value.replaceAll(',', r'\,')}');
      }
    }

    if (genericHeaders.isNotEmpty) {
      args.add('--http-header-fields=${genericHeaders.join(',')}');
    }
    return args;
  }

  void _attachLinuxExternalProcess(Process process) {
    _stopLinuxExternalPlayback(updateState: false);
    _linuxExternalProcess = process;
    _usingLinuxExternalPlayback = true;
    process.stdout.drain<void>().catchError((_) {});
    process.stderr.drain<void>().catchError((_) {});
    unawaited(process.exitCode.then((_) {
      if (_linuxExternalProcess == process) {
        _stopLinuxExternalPlayback(updateState: true);
      }
    }));
  }

  void _startLinuxExternalProgress(Music track) {
    _linuxExternalPlaybackTimer?.cancel();
    _duration = track.duration ?? _duration;
    _durationNotifier.value = _duration;
    _setLocalPlayingState(true);
    _syncExternalPlaybackState(playing: true, position: _position);

    _linuxExternalPlaybackTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_usingLinuxExternalPlayback || !_isPlaying) return;
      final next = _position + const Duration(seconds: 1);
      if (_duration > Duration.zero && next >= _duration) {
        _position = _duration;
        _positionNotifier.value = _position;
        _syncExternalPlaybackState(playing: false, position: _position);
        _stopLinuxExternalPlayback(updateState: true);
        unawaited(_handleBackendCompleted());
        return;
      }
      _position = next;
      _positionNotifier.value = next;
      _resumeTrackId = _queueKey(track);
      _resumePosition = next;
      _syncExternalPlaybackState(playing: true, position: next);
      notifyListeners();
    });
  }

  void _stopLinuxExternalPlayback({required bool updateState}) {
    _linuxExternalPlaybackTimer?.cancel();
    _linuxExternalPlaybackTimer = null;
    final process = _linuxExternalProcess;
    _linuxExternalProcess = null;
    _usingLinuxExternalPlayback = false;
    if (process != null) {
      try {
        process.kill();
      } catch (_) {}
    }
    if (updateState) {
      _setLocalPlayingState(false);
      _syncExternalPlaybackState(playing: false, position: _position);
      notifyListeners();
    }
  }

  List<String> _bundledLinuxMpvCandidates() {
    if (!Platform.isLinux) return const [];

    final candidates = <String>[];
    void addIfExecutable(String path) {
      if (path.trim().isEmpty) return;
      final file = File(path);
      if (file.existsSync()) candidates.add(file.path);
    }

    final exeDir = File(Platform.resolvedExecutable).parent;
    for (final base in <Directory>[
      exeDir,
      Directory(p.join(exeDir.path, 'data')),
      Directory.current,
      Directory(p.join(Directory.current.path, 'linux', 'packaged')),
    ]) {
      addIfExecutable(p.join(base.path, 'tools', 'mpv', 'bin', 'mpv'));
      addIfExecutable(p.join(base.path, 'mpv', 'bin', 'mpv'));
      addIfExecutable(p.join(base.path, 'tools', 'mpv', 'mpv'));
      addIfExecutable(p.join(base.path, 'mpv', 'mpv'));
    }

    return candidates.toSet().toList();
  }

  void _startNativeAudioProgressTicker() {
    if (!_usingNativeWindowsAudio) return;
    _nativeAudioProgressTimer?.cancel();
    _nativeAudioLastProgressTick = DateTime.now();
    _syncNativeAudioPositionFromHandler();
    _nativeAudioProgressTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
      _tickNativeAudioProgress();
    });
  }

  void _stopNativeAudioProgressTicker({bool syncPosition = false}) {
    _nativeAudioProgressTimer?.cancel();
    _nativeAudioProgressTimer = null;
    _nativeAudioLastProgressTick = null;
    if (syncPosition) {
      _syncNativeAudioPositionFromHandler();
    }
  }

  void _tickNativeAudioProgress() {
    if (!_usingNativeWindowsAudio) {
      _stopNativeAudioProgressTicker();
      return;
    }

    final now = DateTime.now();
    final lastTick = _nativeAudioLastProgressTick ?? now;
    _nativeAudioLastProgressTick = now;

    if (!_isPlaying || _suppressPositionUpdatesForTrackChange) {
      return;
    }

    final handlerDuration = _audioHandler.duration;
    if (handlerDuration != null && handlerDuration > Duration.zero) {
      _duration = handlerDuration;
      _durationNotifier.value = handlerDuration;
      _cacheCurrentTrackDuration(handlerDuration);
    } else {
      final trackDuration = currentMusic?.duration;
      if (_duration <= Duration.zero &&
          trackDuration != null &&
          trackDuration > Duration.zero) {
        _duration = trackDuration;
        _durationNotifier.value = trackDuration;
      }
    }

    final handlerPosition = _audioHandler.position;
    final elapsed = now.difference(lastTick);
    var nextPosition = _position;
    if (handlerPosition > Duration.zero &&
        (handlerPosition >= _position ||
            (_position - handlerPosition).inMilliseconds.abs() > 700)) {
      nextPosition = handlerPosition;
    } else if (elapsed > Duration.zero) {
      nextPosition = _position + elapsed;
    }

    if (_duration > Duration.zero && nextPosition > _duration) {
      nextPosition = _duration;
    }

    _applyNativeAudioPosition(nextPosition);

    if (_duration > Duration.zero &&
        nextPosition >= _duration - const Duration(milliseconds: 180)) {
      unawaited(_handleBackendCompleted());
    }
  }

  void _syncNativeAudioPositionFromHandler() {
    if (!_usingNativeWindowsAudio) return;

    final handlerDuration = _audioHandler.duration;
    if (handlerDuration != null && handlerDuration > Duration.zero) {
      _duration = handlerDuration;
      _durationNotifier.value = handlerDuration;
      _cacheCurrentTrackDuration(handlerDuration);
    }

    final handlerPosition = _audioHandler.position;
    if (handlerPosition > Duration.zero || _position == Duration.zero) {
      _applyNativeAudioPosition(handlerPosition);
    }
  }

  void _applyNativeAudioPosition(Duration position) {
    var boundedPosition = position < Duration.zero ? Duration.zero : position;
    if (_duration > Duration.zero && boundedPosition > _duration) {
      boundedPosition = _duration;
    }

    final now = DateTime.now();
    final shouldUpdateNotifier =
        (boundedPosition - _position).inMilliseconds.abs() > 70 ||
            now.difference(_lastPositionUpdate).inMilliseconds > 350;
    _position = boundedPosition;
    if (shouldUpdateNotifier) {
      _positionNotifier.value = boundedPosition;
      _lastPositionUpdate = now;
    }

    final current = currentMusic;
    if (current != null) {
      _resumeTrackId = _queueKey(current);
      _resumePosition = boundedPosition;
    }

    if (now.difference(_lastExternalPlaybackUpdate).inMilliseconds > 350) {
      _lastExternalPlaybackUpdate = now;
      _syncExternalPlaybackState(position: boundedPosition);
    }

    if (now.difference(_lastPlaybackPersistUpdate).inMilliseconds > 1200) {
      _lastPlaybackPersistUpdate = now;
      _savePlaybackDebounced();
    }
  }

  Future<void> _scheduleUpdateNow() async {
    _effectsUpdateTimer?.cancel();
    _hasPendingUpdate = false;
    await _applyScheduledEffects();
  }

  Future<void> _clearNowPlaying() async {
    try {
      _clearSongGapCountdown();
      _stopLinuxExternalPlayback(updateState: false);
      _stopNativeAudioProgressTicker(syncPosition: true);
      _usingNativeWindowsAudio = false;
      _videoPlayback.reset();
      await _audioHandler.stop();
      await _mediaPlayer.stop();
    } catch (_) {}
  }

  void _resetFailedOpenState(Music track) {
    final trackKey = _queueKey(track);
    if (_openedMusicId == trackKey) {
      _openedMusicId = null;
    }
    if (_resumeTrackId == trackKey) {
      _resumeTrackId = null;
      _resumePosition = Duration.zero;
      _shouldResumeCurrentTrack = false;
    }
    if (_isVideoTrack(track)) {
      _videoPlayback.reset();
    }
    _stopNativeAudioProgressTicker(syncPosition: false);
    _usingNativeWindowsAudio = false;
    _setLocalPlayingState(false);
  }

  Future<void> _playCurrentBackend() async {
    if (_usingLinuxExternalPlayback) {
      _setLocalPlayingState(true);
      _syncExternalPlaybackState(playing: true, position: _position);
      return;
    }
    if (_usingNativeWindowsAudio) {
      try {
        await _audioHandler.playFromService();
        _syncNativeAudioPositionFromHandler();
        _startNativeAudioProgressTicker();
      } catch (error) {
        await _switchNativeAudioToMediaKitAfterFailure(error);
        await _mediaPlayer.play();
        unawaited(_scheduleUpdateNow());
      }
      _setLocalPlayingState(true);
      return;
    }
    _playbackDebug(
      '_playCurrentBackend media_kit play() hasVideo=${_videoPlayback.hasVideoTrack} controllerReady=${_videoPlayback.controllerReady}',
    );
    await _mediaPlayer.play();
    if (_videoPlayback.hasVideoTrack) {
      _videoPlayback.startSurfaceSizeProbe(reason: 'play');
    }
    final started = await _waitForMediaKitPlaybackStart();
    if (!started) {
      _playbackDebug('_playCurrentBackend start timeout -> recovery');
      await _recoverMediaKitPlaybackStartFailure();
    } else {
      _playbackDebug('_playCurrentBackend started');
    }
    unawaited(_scheduleUpdateNow());
    _setLocalPlayingState(true);
  }

  Future<void> _pauseCurrentBackend() async {
    if (_usingLinuxExternalPlayback) {
      _stopLinuxExternalPlayback(updateState: true);
      return;
    }
    if (_usingNativeWindowsAudio) {
      await _audioHandler.pauseFromService();
      _stopNativeAudioProgressTicker(syncPosition: true);
      _setLocalPlayingState(false);
      return;
    }
    await _mediaPlayer.pause();
    _setLocalPlayingState(false);
  }

  Future<void> _switchNativeAudioToMediaKitAfterFailure(Object failure) async {
    final track = currentMusic;
    if (track == null) {
      throw StateError(
          'Native audio playback failed and no current track is selected: $failure');
    }

    final fallbackPosition = _audioHandler.position > Duration.zero
        ? _audioHandler.position
        : _position;
    debugPrint('Native audio playback failed, using media_kit: $failure');
    _stopNativeAudioProgressTicker(syncPosition: true);
    _usingNativeWindowsAudio = false;
    await _audioHandler.stop();
    await _audioHandler.updateNowPlaying(
      track,
      playing: false,
      position: fallbackPosition,
      duration: track.duration ?? _duration,
    );
    await _applyDecoderSettings(_mediaPlayer);
    await _openMediaKitPath(
      _mediaPlayer,
      track,
      play: false,
    );
    if (fallbackPosition > Duration.zero) {
      await _mediaPlayer.seek(fallbackPosition);
      _position = fallbackPosition;
      _positionNotifier.value = fallbackPosition;
    }
    await _applyAudioEffects(_mediaPlayer);
    await _setOutputVolume(_volume);
    _syncExternalPlaybackState(playing: false, position: fallbackPosition);
  }

  Future<bool> _waitForMediaKitPlaybackStart({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (_usingLinuxExternalPlayback || _usingNativeWindowsAudio) return true;
    final completer = Completer<bool>();
    late final StreamSubscription<bool> subscription;
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    subscription = _mediaPlayer.stream.playing.listen((playing) {
      if (playing && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    final result = await completer.future;
    timer.cancel();
    await subscription.cancel();
    _playbackDebug('_waitForMediaKitPlaybackStart result=$result');
    return result;
  }

  Future<void> _recoverMediaKitPlaybackStartFailure() async {
    final track = currentMusic;
    if (track == null) return;

    _playbackDebug('playback recovery: reopen current track');
    try {
      final resumeFrom = _position;
      await _openTrackMedia(track);
      if (resumeFrom > Duration.zero) {
        await _mediaPlayer.seek(resumeFrom);
      }
      await _mediaPlayer.play();
      final recovered = await _waitForMediaKitPlaybackStart(
        timeout: const Duration(seconds: 3),
      );
      if (recovered) {
        _playbackDebug('playback recovery success after reopen+play');
        return;
      }
      _playbackDebug('playback recovery forcing open(play:true)');
      await _openMediaKitPath(
        _mediaPlayer,
        track,
        play: true,
      );
      if (resumeFrom > Duration.zero) {
        await _mediaPlayer.seek(resumeFrom);
      }
      await _waitForMediaKitPlaybackStart(timeout: const Duration(seconds: 3));
    } catch (error) {
      _playbackDebug('playback recovery failed: $error');
    }
  }

  void _playbackDebug(String message) {
    if (!_debugPlayback) return;
    debugPrint('PLAYBACK_DEBUG: $message');
  }

  Future<void> _seekCurrentBackend(Duration position) async {
    if (_usingLinuxExternalPlayback) {
      _position = position;
      _positionNotifier.value = position;
      final current = currentMusic;
      if (current != null && _isPlaying) {
        if (_isVideoTrack(current)) {
          await _openLinuxExternalVideo(current, startPosition: position);
        } else {
          await _openLinuxExternalAudio(current, startPosition: position);
        }
      }
      _syncExternalPlaybackState(position: position);
      return;
    }
    if (_usingNativeWindowsAudio) {
      await _audioHandler.seekFromService(position);
      _position = position;
      _positionNotifier.value = position;
      _nativeAudioLastProgressTick = DateTime.now();
      _syncExternalPlaybackState(position: position);
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
    unawaited(_audioHandler.setWindowsMediaControlsActive(true));
    _ensureQueueInitialized();
    try {
      final track = _musicList[_currentIndex];
      final trackId = _queueKey(track);
      _playbackDebug(
        'play() index=$_currentIndex title="${track.title}" opened=$_openedMusicId target=$trackId isPlaying=$_isPlaying',
      );
      _usingNativeWindowsAudio = _shouldUseNativeWindowsAudio(track);

      if (_openedMusicId == trackId) {
        if (_shouldResumeCurrentTrack) {
          await _applyResumePositionIfNeeded(trackId);
        }
        await _smoothPlayCurrentBackend();
        _musicList[_currentIndex].lastPlayed = DateTime.now();
        _shouldResumeCurrentTrack = false;
        _refreshRecommendations();
        _saveStats();
        _savePlaybackDebounced();
        notifyListeners();
        return;
      }

      final startPosition =
          (_shouldResumeCurrentTrack && _resumeTrackId == trackId)
              ? _resumePosition
              : Duration.zero;
      if (_shouldOpenLinuxVideoExternally(track)) {
        await _openLinuxExternalVideo(track, startPosition: startPosition);
        _openedMusicId = trackId;
        track.playCount++;
        track.lastPlayed = DateTime.now();
        _refreshRecommendations();
        _resumeTrackId = trackId;
        _resumePosition = Duration.zero;
        _shouldResumeCurrentTrack = false;
        _saveStats();
        _savePlaybackDebounced();
        notifyListeners();
        return;
      }

      _videoPlayback.setCurrentTrack(track);
      await _smoothOpenAndPlay(track, startPosition, playAfterOpen: true);
      _openedMusicId = trackId;

      track.playCount++;
      track.lastPlayed = DateTime.now();
      _refreshRecommendations();
      _resumeTrackId = trackId;
      _resumePosition = _position;
      _shouldResumeCurrentTrack = false;
      _scheduleUpdate();
      _saveStats();
      _savePlaybackDebounced();
      notifyListeners();
    } catch (e) {
      debugPrint('Play Error: $e');
      if (_musicList.isNotEmpty) {
        _resetFailedOpenState(_musicList[_currentIndex]);
      }
      if (_musicList.isNotEmpty) {
        await _tryOpenLinuxExternalVideoAfterFailure(
          _musicList[_currentIndex],
          e,
          startPosition: _position,
        );
      }
      await _tryOpenLinuxExternalAudioAfterFailure(e);
    }
  }

  Future<void> _playStreamingCurrent() async {
    final track = _streamingMusic;
    if (track == null) return;
    _usingNativeWindowsAudio = false;

    try {
      final trackId = _queueKey(track);
      if (_shouldOpenLinuxAudioExternally(track)) {
        await _openLinuxExternalAudio(track);
        _openedMusicId = trackId;
        _resumeTrackId = trackId;
        _resumePosition = Duration.zero;
        _shouldResumeCurrentTrack = false;
        notifyListeners();
        return;
      }

      if (_shouldOpenLinuxVideoExternally(track)) {
        await _openLinuxExternalVideo(track);
        _openedMusicId = trackId;
        _resumeTrackId = trackId;
        _resumePosition = Duration.zero;
        _shouldResumeCurrentTrack = false;
        notifyListeners();
        return;
      }

      if (_openedMusicId == trackId) {
        await _playCurrentBackend();
        notifyListeners();
        return;
      }

      _videoPlayback.setCurrentTrack(track);
      _position = Duration.zero;
      _positionNotifier.value = Duration.zero;
      _duration = track.duration ?? Duration.zero;
      _durationNotifier.value = _duration;
      await _smoothOpenAndPlay(track, Duration.zero, playAfterOpen: true);
      _openedMusicId = trackId;

      _resumeTrackId = trackId;
      _resumePosition = Duration.zero;
      _shouldResumeCurrentTrack = false;
      _scheduleUpdate();
      notifyListeners();
    } catch (e) {
      debugPrint('Stream Play Error: $e');
      _resetFailedOpenState(track);
      await _tryOpenLinuxExternalVideoAfterFailure(
        track,
        e,
        startPosition: _position,
      );
      await _tryOpenLinuxExternalAudioAfterFailure(e);
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
    _playbackDebug(
      '_runPlaybackCommand enter active=$_isPlaybackCommandActive dropIfActive=$dropIfActive pending=${_pendingPlaybackCommand != null}',
    );
    if (_isPlaybackCommandActive) {
      if (dropIfActive) return;
      _pendingPlaybackCommand = action;
      _playbackDebug('_runPlaybackCommand queued pending command');
      return;
    }
    _isPlaybackCommandActive = true;
    try {
      do {
        _pendingPlaybackCommand = null;
        _playbackDebug('_runPlaybackCommand executing command');
        await action();
        action = _pendingPlaybackCommand ?? action;
      } while (_pendingPlaybackCommand != null);
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 35));
      _isPlaybackCommandActive = false;
      _playbackDebug('_runPlaybackCommand exit');
    }
  }

  Future<void> _togglePlayPauseInternal() async {
    if (!_isPlaying && currentMusic != null) {
      final currentKey = _queueKey(currentMusic!);
      if (_openedMusicId != currentKey) {
        await play();
        return;
      }
      if (_shouldResumeCurrentTrack) {
        await _applyResumePositionIfNeeded(currentKey);
      }
      _shouldResumeCurrentTrack = false;
      await _smoothPlayCurrentBackend();
    } else if (_isPlaying && currentMusic != null) {
      _resumeTrackId = _queueKey(currentMusic!);
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
    final current = currentMusic;
    _resumeTrackId = current == null ? null : _queueKey(current);
    _resumePosition = position;
    _shouldResumeCurrentTrack = position > Duration.zero;
    if (_streamingMusic == null) {
      _savePlaybackDebounced();
    }
    notifyListeners();
  }

  void setVolume(double volume) {
    final previous = _volume;
    final maxVolume =
        _safeEarsEnabled ? _safeEarsMaxVolume.clamp(35.0, 100.0) : 100.0;
    _volume = volume.clamp(0.0, maxVolume).toDouble();
    if (_volume > 0.5) {
      _lastAudibleVolume = _volume;
    }
    _volumeNotifier.value = _volume;
    _updateSnapshot();
    unawaited(_smoothSetUserVolume(previous, _volume));
  }

  void adjustVolumeBy(double delta) {
    setVolume(_volume + delta);
  }

  void toggleMute() {
    if (_volume > 0.5) {
      _lastAudibleVolume = _volume;
      setVolume(0);
      return;
    }
    setVolume(_lastAudibleVolume.clamp(5.0, 100.0).toDouble());
  }

  Future<void> _smoothSetUserVolume(double from, double to) async {
    final generation = ++_volumeChangeGeneration;
    if ((from - to).abs() < 0.5) {
      await _setBackendVolume(to, internal: true);
      return;
    }

    const duration = Duration(milliseconds: 140);
    const steps = 8;
    for (var i = 1; i <= steps; i++) {
      if (generation != _volumeChangeGeneration) return;
      final t = i / steps;
      final eased = t * t * (3 - (2 * t));
      await _setBackendVolume(from + ((to - from) * eased), internal: true);
      await Future<void>.delayed(
        Duration(milliseconds: duration.inMilliseconds ~/ steps),
      );
    }
    if (generation == _volumeChangeGeneration) {
      await _setBackendVolume(to, internal: true);
    }
  }

  void next() {
    unawaited(_runPlaybackCommand(_nextInternal));
  }

  Future<void> _nextInternal() async {
    if (_streamingMusic != null) {
      await _moveInStreamingQueue(1);
      return;
    }
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
      if (_position >= const Duration(seconds: 3)) {
        seekTo(Duration.zero);
      } else {
        await _moveInStreamingQueue(-1);
      }
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
      if (!forcePrevious && _position >= const Duration(seconds: 3)) {
        seekTo(Duration.zero);
      } else {
        await _moveInStreamingQueue(-1);
      }
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
      for (final music in _musicList) _rememberedTrackKey(music.filePath): music
    };
    final keepRememberedVisible =
        clearExisting && customPaths == null && _musicList.isNotEmpty;
    if (clearExisting && !keepRememberedVisible) {
      _musicList = [];
      _systemMusicCount = 0;
    }
    _invalidateDataCache();
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
          _invalidateDataCache();
          if (throttleTimer == null || !throttleTimer!.isActive) {
            notifyListeners();
            throttleTimer = Timer(const Duration(milliseconds: 800), () {});
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
    _refreshRecommendations();

    _isLoadingSystemMusic = false;
    _syncQueueWithLibrary(previousCurrentId: previousCurrentId);
    _refreshSystemPlaylistsInternal();
    await _restorePlaybackStateIfNeeded();
    await _saveLibrarySnapshot();
    _invalidateDataCache();
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
    _activeQueueIds = _musicList.map(_queueKey).toList();
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
    _invalidateDataCache();
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
      year: track.year,
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

      final dir = await getPlayerVfDocumentsDirectory();
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
    _invalidateDataCache();
    notifyListeners();
    await loadSystemMusic(customPaths: _lastUsedPaths);
  }

  Future<bool> deleteMusic(int index, {bool deleteFile = false}) async {
    if (index < 0 || index >= _musicList.length) return false;

    final music = _musicList[index];
    final removedKey = _queueKey(music);
    final isCurrentTrack =
        currentMusic != null && _queueKey(currentMusic!) == removedKey;

    if (deleteFile) {
      if (kIsWeb || _isTransientWebPath(music.filePath)) return false;
      if (music.filePath.startsWith('http://') ||
          music.filePath.startsWith('https://')) {
        return false;
      }

      final file = File(music.filePath);
      try {
        if (await file.exists()) {
          if (isCurrentTrack) {
            await _pauseCurrentBackend();
            await _clearNowPlaying();
          }
          await file.delete();
        }
      } catch (e) {
        debugPrint('Error deleting music file: $e');
        return false;
      }
    }

    if (_openedMusicId == removedKey) {
      _openedMusicId = null;
    }
    if (_resumeTrackId == removedKey) {
      _clearResumeState();
    }
    _musicList.removeAt(index);
    if (_currentIndex >= _musicList.length) {
      _currentIndex = max(0, _musicList.length - 1);
    }
    _activeQueueIds.remove(removedKey);
    _shuffledQueueIds.remove(removedKey);
    _syncQueueWithLibrary();
    _refreshSystemPlaylistsInternal();
    _savePlaybackDebounced();
    _invalidateDataCache();
    await _saveLibrarySnapshot();
    notifyListeners();
    return true;
  }

  Future<void> updateMusicMetadata(
    String id,
    String title,
    String artist,
    String album,
    String genre, {
    String? year,
  }) async {
    final index = _musicList.indexWhere((music) => music.id == id);
    if (index != -1) {
      final old = _musicList[index];
      _musicList[index] = Music(
        id: old.id,
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        year: year ?? old.year,
        filePath: old.filePath,
        coverPath: old.coverPath,
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
      year: old.year,
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
  }

  void refreshSystemPlaylists() {
    _refreshSystemPlaylistsInternal();
    notifyListeners();
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
        startQueue(list, startMusicId: _queueKey(list.first), playlistId: id);
        await play();
      }));
    }
  }

  void playMusicFromQueue(List<Music> queue, Music target,
      {String? playlistId}) {
    unawaited(_runPlaybackCommand(() async {
      final targetKey = _queueKey(target);
      final targetIndex = _findMusicIndexByQueueKey(targetKey);
      if (targetIndex == -1) {
        debugPrint(
            'playMusicFromQueue: target not found in library: $targetKey');
        return;
      }

      // Keep queue stable, but ensure the requested target always exists inside it.
      final normalizedQueue = <Music>[
        ...queue.where((m) => _findMusicIndexByQueueKey(_queueKey(m)) != -1),
      ];
      final hasTarget =
          normalizedQueue.any((music) => _queueKey(music) == targetKey);
      if (!hasTarget) {
        normalizedQueue.insert(0, _musicList[targetIndex]);
      }

      startQueue(
        normalizedQueue,
        startMusicId: targetKey,
        playlistId: playlistId,
      );
      await play();
    }));
  }

  Future<void> playStreamingMusic(Music music) async {
    _streamingMusic = music;
    _streamingQueue = [music];
    _currentPlaylistId = null;
    _activeQueueIds = [_queueKey(music)];
    _shuffledQueueIds = [_queueKey(music)];
    _clearResumeState(keepOpenedTrack: false);
    notifyListeners();
    await _playStreamingCurrent();
  }

  Future<void> replaceStreamingMusic(
    Music music, {
    Duration? startPosition,
    bool? shouldPlay,
  }) async {
    final current = currentMusic;
    final samePath = current != null &&
        _canonicalMediaPathKey(current.filePath) ==
            _canonicalMediaPathKey(music.filePath);
    if (samePath) {
      _playbackDebug(
        'replaceStreamingMusic skipped (same source) title="${music.title}"',
      );
      return;
    }
    final targetPosition = startPosition ?? _position;
    final playAfterOpen = shouldPlay ?? _isPlaying;
    _streamingMusic = music;
    _streamingQueue = [music];
    _currentPlaylistId = null;
    _activeQueueIds = [_queueKey(music)];
    _shuffledQueueIds = [_queueKey(music)];
    _usingNativeWindowsAudio = false;
    _videoPlayback.setCurrentTrack(music);
    _position = targetPosition;
    _positionNotifier.value = targetPosition;
    _duration = music.duration ?? _duration;
    _durationNotifier.value = _duration;
    _openedMusicId = null;
    notifyListeners();

    if (_shouldOpenLinuxAudioExternally(music)) {
      await _openLinuxExternalAudio(music, startPosition: targetPosition);
      final musicKey = _queueKey(music);
      _openedMusicId = musicKey;
      _resumeTrackId = musicKey;
      _resumePosition = Duration.zero;
      _shouldResumeCurrentTrack = false;
      notifyListeners();
      return;
    }

    if (_shouldOpenLinuxVideoExternally(music)) {
      await _openLinuxExternalVideo(music, startPosition: targetPosition);
      final musicKey = _queueKey(music);
      _openedMusicId = musicKey;
      _resumeTrackId = musicKey;
      _resumePosition = Duration.zero;
      _shouldResumeCurrentTrack = false;
      notifyListeners();
      return;
    }

    var openedSuccessfully = false;
    try {
      await _smoothOpenAndPlay(
        music,
        targetPosition,
        playAfterOpen: playAfterOpen,
      );
      openedSuccessfully = true;
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
    } catch (e) {
      debugPrint('Replace streaming media_kit failed: $e');
      _resetFailedOpenState(music);
      await _tryOpenLinuxExternalVideoAfterFailure(
        music,
        e,
        startPosition: targetPosition,
      );
      await _tryOpenLinuxExternalAudioAfterFailure(e);
    }
    if (!openedSuccessfully) {
      notifyListeners();
      return;
    }

    final musicKey = _queueKey(music);
    _openedMusicId = musicKey;
    _resumeTrackId = musicKey;
    _resumePosition = targetPosition;
    _shouldResumeCurrentTrack = targetPosition > Duration.zero;
    if (!playAfterOpen) {
      await _smoothPauseCurrentBackend();
    }
    _scheduleUpdate();
    notifyListeners();
  }

  Future<void> replaceStreamingQueue(
    List<Music> queue,
    Music target, {
    Duration? startPosition,
    bool? shouldPlay,
  }) async {
    final normalizedQueue = queue
        .where((music) => music.filePath.trim().isNotEmpty)
        .toList(growable: false);
    final targetKey = _queueKey(target);
    final resolvedTarget = normalizedQueue.firstWhere(
      (music) => _queueKey(music) == targetKey,
      orElse: () => target,
    );
    final nextQueue = normalizedQueue.any(
      (music) => _queueKey(music) == _queueKey(resolvedTarget),
    )
        ? normalizedQueue
        : [resolvedTarget, ...normalizedQueue];
    final current = currentMusic;
    final samePath = current != null &&
        _canonicalMediaPathKey(current.filePath) ==
            _canonicalMediaPathKey(resolvedTarget.filePath);

    if (samePath) {
      _streamingMusic = resolvedTarget;
      _streamingQueue = nextQueue;
      _activeQueueIds = nextQueue.map(_queueKey).toList();
      _shuffledQueueIds = List<String>.from(_activeQueueIds);
      if (startPosition != null) seekTo(startPosition);
      if (shouldPlay != null && shouldPlay != _isPlaying) {
        togglePlayPause();
      }
      notifyListeners();
      return;
    }

    await replaceStreamingMusic(
      resolvedTarget,
      startPosition: startPosition,
      shouldPlay: shouldPlay,
    );
    _streamingQueue = nextQueue;
    _activeQueueIds = nextQueue.map(_queueKey).toList();
    _shuffledQueueIds = List<String>.from(_activeQueueIds);
    notifyListeners();
  }

  void startQueue(List<Music> queue,
      {String? startMusicId, String? playlistId}) {
    _streamingMusic = null;
    _streamingQueue = [];
    final ids = queue
        .map(_queueKey)
        .where((id) => _findMusicIndexByQueueKey(id) != -1)
        .toList();
    if (ids.isEmpty) return;

    _activeQueueIds = ids;
    _currentPlaylistId = playlistId;
    final selectedId = startMusicId ?? ids.first;
    final actualIndex = _findMusicIndexByQueueKey(selectedId);
    if (actualIndex != -1) {
      final current = currentMusic;
      final currentKey = current == null ? null : _queueKey(current);
      if (_queueKey(_musicList[actualIndex]) != currentKey) {
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
    final index = _findMusicIndexByQueueKey(musicId);
    if (index == -1) return;
    final musicKey = _queueKey(_musicList[index]);
    _ensureQueueInitialized();

    _activeQueueIds.remove(musicKey);
    final current = currentMusic;
    final currentId = current == null ? null : _queueKey(current);
    final insertIndex = currentId == null
        ? _activeQueueIds.length
        : _activeQueueIds.indexOf(currentId) + 1;
    final safeIndex = insertIndex.clamp(0, _activeQueueIds.length);
    _activeQueueIds.insert(safeIndex, musicKey);
    _rebuildShuffledQueue();
    _savePlaybackDebounced();
    notifyListeners();
  }

  void addAllToQueue(Iterable<Music> tracks) {
    if (_streamingMusic != null) return;
    final incomingIds = tracks
        .map(_queueKey)
        .where((id) => _findMusicIndexByQueueKey(id) != -1)
        .toList(growable: false);
    if (incomingIds.isEmpty) return;

    _ensureQueueInitialized();
    final current = currentMusic;
    final currentId = current == null ? null : _queueKey(current);
    final uniqueIncoming = <String>[];
    for (final id in incomingIds) {
      if (!uniqueIncoming.contains(id)) uniqueIncoming.add(id);
    }

    _activeQueueIds.removeWhere(uniqueIncoming.contains);
    final insertIndex = currentId == null
        ? _activeQueueIds.length
        : _activeQueueIds.indexOf(currentId) + 1;
    final safeIndex = insertIndex.clamp(0, _activeQueueIds.length);
    _activeQueueIds.insertAll(safeIndex, uniqueIncoming);
    _rebuildShuffledQueue();
    _savePlaybackDebounced();
    notifyListeners();
  }

  void removeFromQueue(String musicId) {
    if (_streamingMusic != null) return;
    if (_activeQueueIds.length <= 1) return;
    final index = _findMusicIndexByQueueKey(musicId);
    if (index == -1) return;
    final musicKey = _queueKey(_musicList[index]);

    final current = currentMusic;
    final currentId = current == null ? null : _queueKey(current);
    final wasCurrent = currentId == musicKey;
    _activeQueueIds.remove(musicKey);
    _shuffledQueueIds.remove(musicKey);

    if (wasCurrent) {
      final nextId = _activeQueueIds.first;
      final nextIndex = _findMusicIndexByQueueKey(nextId);
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
    if (id == 'music') return musicOnlyList;
    if (id == 'favorites') return favoriteMusicList;
    if (id == 'early_listened') return _cachedEarlyListened;
    if (id == 'videos') return videoMusicList;
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
      _safeEarsEnabled = prefs.getBool(_safeEarsEnabledKey) ?? false;
      _safeEarsMaxVolume = (prefs.getDouble(_safeEarsMaxVolumeKey) ?? 72.0)
          .clamp(35.0, 100.0)
          .toDouble();
      _dspEnabled = prefs.getBool(_dspEnabledKey) ?? true;
      _dspLoudnessNormalizationEnabled = prefs.getBool(_dspLoudnessKey) ?? true;
      _dspLimiterEnabled = prefs.getBool(_dspLimiterKey) ?? true;
      _dspCompressorEnabled = prefs.getBool(_dspCompressorKey) ?? false;
      _dspBass =
          (prefs.getDouble(_dspBassKey) ?? 0.0).clamp(-6.0, 6.0).toDouble();
      _dspMid =
          (prefs.getDouble(_dspMidKey) ?? 0.0).clamp(-6.0, 6.0).toDouble();
      _dspTreble =
          (prefs.getDouble(_dspTrebleKey) ?? 0.0).clamp(-6.0, 6.0).toDouble();
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

      final dir = await getPlayerVfDocumentsDirectory();
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
      final dir = await getPlayerVfDocumentsDirectory();
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
      final dir = await getPlayerVfDocumentsDirectory();
      final file = File('${dir.path}/favorites.json');
      if (await file.exists()) {
        final ids = jsonDecode(await file.readAsString()).cast<String>();
        for (final music in _musicList) {
          music.isFavorite = ids.contains(music.id);
        }
      }
      final dbLikedIds = await UserFeedbackStore.likedTrackIds();
      if (dbLikedIds.isNotEmpty) {
        for (final music in _musicList) {
          if (dbLikedIds.contains(music.id)) music.isFavorite = true;
        }
      }
      final likedTracks = _musicList.where((music) => music.isFavorite);
      if (likedTracks.isNotEmpty) {
        await UserFeedbackStore.saveLikes(likedTracks, true);
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
    }
  }

  void _saveDebounced() {
    _settingsDirty = true;
    _saveSettingsTimer?.cancel();
    _saveSettingsTimer = Timer(const Duration(seconds: 2), _flushDirty);
  }

  void _savePlaybackDebounced() {
    if (!_rememberPlayback) return;
    _playbackDirty = true;
    _savePlaybackTimer?.cancel();
    _savePlaybackTimer = Timer(const Duration(milliseconds: 800), _flushDirty);
  }

  void _flushDirty() {
    if (_settingsDirty) {
      _settingsDirty = false;
      _saveAudioEffectsSettings();
    }
    if (_playbackDirty) {
      _playbackDirty = false;
      _savePlaybackState();
    }
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
      await prefs.setBool(_safeEarsEnabledKey, _safeEarsEnabled);
      await prefs.setDouble(_safeEarsMaxVolumeKey, _safeEarsMaxVolume);
      await prefs.setBool(_dspEnabledKey, _dspEnabled);
      await prefs.setBool(_dspLoudnessKey, _dspLoudnessNormalizationEnabled);
      await prefs.setBool(_dspLimiterKey, _dspLimiterEnabled);
      await prefs.setBool(_dspCompressorKey, _dspCompressorEnabled);
      await prefs.setDouble(_dspBassKey, _dspBass);
      await prefs.setDouble(_dspMidKey, _dspMid);
      await prefs.setDouble(_dspTrebleKey, _dspTreble);
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
      final current = currentMusic;
      final payload = {
        'currentMusicId': current?.id,
        'currentMusicKey': current == null ? null : _queueKey(current),
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
      _windowsMediaControlForeground = false;
      _syncWindowsMediaControlOwnership();
      _savePlaybackState();
      unawaited(_audioHandler.setWindowsMediaControlsActive(false));
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _windowsMediaControlForeground = true;
      _syncWindowsMediaControlOwnership();
      unawaited(_audioHandler.setWindowsMediaControlsActive(_isPlaying));
      _refreshRecommendations(notify: true);
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
        httpHeaders: old.httpHeaders,
        genre: old.genre,
        year: old.year,
        duration: old.duration,
        isFavorite: !old.isFavorite,
        playCount: old.playCount,
        lastPlayed: old.lastPlayed,
        dateAdded: old.dateAdded,
      );
      _invalidateDataCache();
      _refreshRecommendations();
      notifyListeners();
      await _saveLibrarySnapshot();
      await UserFeedbackStore.saveLike(
          _musicList[index], _musicList[index].isFavorite);
      await _saveFavoriteIds();
    }
  }

  Future<void> setFavoriteForMusicIds(
    Iterable<String> ids,
    bool isFavorite,
  ) async {
    final targets = ids.toSet();
    if (targets.isEmpty) return;

    var changed = false;
    for (var i = 0; i < _musicList.length; i++) {
      final old = _musicList[i];
      if (!targets.contains(old.id) || old.isFavorite == isFavorite) {
        continue;
      }
      _musicList[i] = Music(
        id: old.id,
        title: old.title,
        artist: old.artist,
        album: old.album,
        filePath: old.filePath,
        coverPath: old.coverPath,
        httpHeaders: old.httpHeaders,
        genre: old.genre,
        year: old.year,
        duration: old.duration,
        isFavorite: isFavorite,
        playCount: old.playCount,
        lastPlayed: old.lastPlayed,
        dateAdded: old.dateAdded,
      );
      changed = true;
    }
    if (!changed) return;

    _invalidateDataCache();
    _refreshRecommendations();
    notifyListeners();
    await _saveLibrarySnapshot();
    await UserFeedbackStore.saveLikes(
      _musicList.where((music) => targets.contains(music.id)),
      isFavorite,
    );
    await _saveFavoriteIds();
  }

  Future<void> _saveFavoriteIds() async {
    if (kIsWeb) return;
    try {
      final dir = await getPlayerVfDocumentsDirectory();
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

  Future<void> _savePlaylists() async {
    if (kIsWeb) return;

    try {
      final dir = await getPlayerVfDocumentsDirectory();
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
      final dir = await getPlayerVfDocumentsDirectory();
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
        final dir = await getPlayerVfDocumentsDirectory();
        final file = File('${dir.path}/music_library_snapshot.json');
        if (await file.exists()) raw = await file.readAsString();
      }

      if (raw == null || raw.trim().isEmpty) return;

      final List<Music> tracks;
      if (kIsWeb) {
        tracks = _parseLibrarySnapshotFromJson(raw)
            .where((music) => !_isTransientWebPath(music.filePath))
            .toList();
      } else {
        tracks = await compute(_parseLibrarySnapshotFromJson, raw);
      }

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

      final dir = await getPlayerVfDocumentsDirectory();
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
      final old = remembered[_rememberedTrackKey(music.filePath)];
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
      year: scanned.year.isNotEmpty ? scanned.year : old.year,
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
        old.year != refreshed.year ||
        old.coverPath != refreshed.coverPath ||
        old.duration?.inMilliseconds != refreshed.duration?.inMilliseconds;
  }

  bool _isTransientWebPath(String path) => path.startsWith('blob:');

  String _rememberedTrackKey(String path) {
    return _canonicalMediaPathKey(path);
  }

  String? _localFilePathFromMediaPath(String path) =>
      VideoPlaybackService.localFilePathFromMediaPath(path);

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
      final primaryPath = _firstExistingVideoQualityPath(qualities);
      if (primaryPath.isEmpty) return null;
      return _PlayervfVideoManifest(
        path: p.normalize(manifestFile.path),
        primaryPath: primaryPath,
      );
    } catch (_) {
      return null;
    }
  }

  String _firstExistingVideoQualityPath(List qualities) {
    for (final quality in qualities) {
      if (quality is! Map) continue;
      final path = quality['path']?.toString() ?? '';
      if (path.isNotEmpty && File(path).existsSync()) return path;
    }
    return '';
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

  String _queueKey(Music music) {
    final path = _canonicalMediaPathKey(music.filePath);
    if (path.isNotEmpty) return path;
    return music.id;
  }

  int _findMusicIndexByQueueKey(String key) {
    final normalizedKey = _canonicalMediaPathKey(key);
    final pathIndex = _musicList.indexWhere((music) {
      final path = _canonicalMediaPathKey(music.filePath);
      return path.isNotEmpty && path == normalizedKey;
    });
    if (pathIndex != -1) return pathIndex;
    return _musicList.indexWhere((music) => music.id == key);
  }

  String _canonicalMediaPathKey(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final localPath = _localFilePathFromMediaPath(trimmed);
    final normalized = p.normalize(localPath ?? trimmed);
    if (!kIsWeb && Platform.isWindows) {
      return normalized.toLowerCase();
    }
    return normalized;
  }

  String _normalizedYear(String raw) {
    final match = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(raw);
    return match?.group(1) ?? '';
  }

  double _recommendationJitter(Music music) {
    final key = '${_queueKey(music)}:$_recommendationRefreshSeed';
    final digest = md5.convert(utf8.encode(key));
    final value = digest.bytes.take(4).fold<int>(
          0,
          (combined, byte) => (combined << 8) | byte,
        );
    return (value / 0xFFFFFFFF) * 9.0;
  }

  void _refreshRecommendations({bool notify = false}) {
    _recommendationRefreshSeed = DateTime.now().microsecondsSinceEpoch;
    if (notify) notifyListeners();
  }

  int _normalizedUniqueCount(Iterable<String> values) {
    return values
        .map((value) => value.trim().toLowerCase())
        .where((value) =>
            value.isNotEmpty &&
            value != 'unknown' &&
            value != 'unknown artist' &&
            value != 'unknown album')
        .toSet()
        .length;
  }

  double _ratio(num value, num total) {
    if (total <= 0) return 0;
    return (value / total).clamp(0.0, 1.0).toDouble();
  }

  List<StatsRankItem> _rankStrings(
    Iterable<String> values, {
    int top = 8,
  }) {
    final counts = <String, int>{};
    final display = <String, String>{};
    var total = 0;
    for (final raw in values) {
      final label = _normalizedStatsLabel(raw);
      final key = label.toLowerCase();
      total++;
      counts[key] = (counts[key] ?? 0) + 1;
      display[key] = label;
    }
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked
        .take(top)
        .map((entry) => StatsRankItem(
              display[entry.key] ?? entry.key,
              entry.value,
              _ratio(entry.value, total),
            ))
        .toList(growable: false);
  }

  List<StatsRankItem> _playlistRanks(int totalTracks) {
    final ranks = _playlists
        .map((playlist) => StatsRankItem(
              playlist.name,
              playlist.musicIds.length,
              _ratio(playlist.musicIds.length, max(1, totalTracks)),
            ))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranks.take(8).toList(growable: false);
  }

  String _normalizedStatsLabel(String raw) {
    final label = raw.trim();
    final key = label.toLowerCase();
    if (label.isEmpty ||
        key == 'unknown' ||
        key == 'unknown artist' ||
        key == 'unknown album') {
      return 'Unknown';
    }
    return label;
  }

  StatsRankItem _topRankItem(Iterable<String> values, String fallback) {
    final ranks = _rankStrings(values, top: 1);
    if (ranks.isEmpty) return StatsRankItem(fallback, 0, 0);
    return ranks.first;
  }

  List<RecommendationSignalStat> _recommendationSignalStats() {
    final total = _musicList.length;
    if (total == 0) return const [];
    final now = DateTime.now();
    final liked = favoriteMusicList.length;
    final played = _musicList.where((music) => music.playCount > 0).length;
    final recentAdded = _musicList
        .where((music) => now.difference(music.dateAdded).inDays <= 30)
        .length;
    final recentPlayed = _musicList
        .where((music) =>
            music.lastPlayed != null &&
            now.difference(music.lastPlayed!).inDays <= 30)
        .length;
    final likedGenres = favoriteMusicList
        .map((music) => _normalizedStatsLabel(music.genre).toLowerCase())
        .where((genre) => genre != 'unknown')
        .toSet()
        .length;
    final likedArtists = favoriteMusicList
        .map((music) => _normalizedStatsLabel(music.artist).toLowerCase())
        .where((artist) => artist != 'unknown')
        .toSet()
        .length;
    final likedYears = favoriteMusicList
        .map((music) => _normalizedYear(music.year))
        .where((year) => year.isNotEmpty)
        .toSet()
        .length;

    return [
      RecommendationSignalStat('Likes', liked, _ratio(liked, total)),
      RecommendationSignalStat(
          'Liked genres', likedGenres, _ratio(likedGenres, max(1, genreCount))),
      RecommendationSignalStat('Liked artists', likedArtists,
          _ratio(likedArtists, max(1, artistCount))),
      RecommendationSignalStat(
          'Liked years', likedYears, _ratio(likedYears, max(1, yearCount))),
      RecommendationSignalStat('Play count', played, _ratio(played, total)),
      RecommendationSignalStat(
          'Recently added', recentAdded, _ratio(recentAdded, total)),
      RecommendationSignalStat(
          'Recently played', recentPlayed, _ratio(recentPlayed, total)),
      RecommendationSignalStat('Video signal', videoMusicList.length,
          _ratio(videoMusicList.length, total)),
    ];
  }

  int get genreCount => _normalizedUniqueCount(_musicList.map((m) => m.genre));
  int get artistCount =>
      _normalizedUniqueCount(_musicList.map((m) => m.artist));
  int get yearCount => _normalizedUniqueCount(_musicList.map((m) => m.year));

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
      final index = _findMusicIndexByQueueKey(id);
      if (index != -1) {
        tracks.add(_musicList[index]);
      }
    }
    return tracks;
  }

  void _ensureQueueInitialized() {
    if (_activeQueueIds.isEmpty && _musicList.isNotEmpty) {
      _activeQueueIds = _musicList.map(_queueKey).toList();
      _rebuildShuffledQueue();
    }
  }

  void _rebuildShuffledQueue() {
    final baseQueue = List<String>.from(_activeQueueIds);
    if (baseQueue.isEmpty) {
      _shuffledQueueIds = [];
      return;
    }

    final current = currentMusic;
    final currentId = current == null ? null : _queueKey(current);
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

    final current = currentMusic;
    final currentId = current == null ? null : _queueKey(current);
    var queueIndex = currentId == null ? -1 : order.indexOf(currentId);
    if (queueIndex == -1) queueIndex = 0;

    final targetIndex = queueIndex + direction;
    if (targetIndex < 0) {
      if (!_isRepeatAll) return false;
      final loopIndex = _findMusicIndexByQueueKey(order.last);
      if (loopIndex == -1) return false;
      _currentIndex = loopIndex;
      return true;
    }

    if (targetIndex >= order.length) {
      if (!_isRepeatAll) {
        unawaited(_pauseCurrentBackend());
        final current = currentMusic;
        final currentKey = current == null ? null : _queueKey(current);
        _openedMusicId = currentKey;
        _resumeTrackId = currentKey;
        _resumePosition = Duration.zero;
        seekTo(Duration.zero);
        return false;
      }
      final loopIndex = _findMusicIndexByQueueKey(order.first);
      if (loopIndex == -1) return false;
      _currentIndex = loopIndex;
      return true;
    }

    final actualIndex = _findMusicIndexByQueueKey(order[targetIndex]);
    if (actualIndex == -1) return false;
    _currentIndex = actualIndex;
    return true;
  }

  Future<void> _moveInStreamingQueue(int direction) async {
    if (_streamingQueue.isEmpty) return;

    final current = _streamingMusic ?? currentMusic;
    final currentId = current == null ? null : _queueKey(current);
    var queueIndex = currentId == null
        ? -1
        : _streamingQueue.indexWhere((music) => _queueKey(music) == currentId);
    if (queueIndex == -1) queueIndex = 0;

    final targetIndex = queueIndex + direction;
    final queue = List<Music>.from(_streamingQueue);
    if (targetIndex < 0) {
      if (!_isRepeatAll) return;
      await replaceStreamingQueue(queue, queue.last);
      return;
    }

    if (targetIndex >= _streamingQueue.length) {
      if (!_isRepeatAll) {
        unawaited(_pauseCurrentBackend());
        seekTo(Duration.zero);
        return;
      }
      await replaceStreamingQueue(queue, queue.first);
      return;
    }

    await replaceStreamingQueue(queue, queue[targetIndex]);
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
    if (!_shouldAcceptBackendCompleted()) return;

    final current = currentMusic;
    final trackId = current == null ? null : _queueKey(current);
    if (trackId == null || _completedTrackId == trackId) return;

    _completedTrackId = trackId;
    await _runPlaybackCommand(_handleTrackCompleted);
  }

  bool _shouldAcceptBackendCompleted() {
    if (_suppressPositionUpdatesForTrackChange) {
      _playbackDebug('completed ignored during track transition');
      return false;
    }

    final current = currentMusic;
    if (current == null) return false;
    final currentKey = _queueKey(current);
    if (_openedMusicId != null && _openedMusicId != currentKey) {
      _playbackDebug(
        'completed ignored for stale backend opened=$_openedMusicId current=$currentKey',
      );
      return false;
    }

    final openedAt = _lastTrackOpenStartedAt;
    if (openedAt != null &&
        DateTime.now().difference(openedAt) <
            const Duration(milliseconds: 900)) {
      _playbackDebug('completed ignored immediately after opening track');
      return false;
    }

    final duration = _duration > Duration.zero
        ? _duration
        : current.duration ?? Duration.zero;
    if (duration <= Duration.zero) return true;

    final tolerance = duration < const Duration(seconds: 5)
        ? const Duration(milliseconds: 350)
        : const Duration(milliseconds: 1500);
    final nearEnd = _position >= duration - tolerance;
    if (!nearEnd) {
      _playbackDebug(
        'completed ignored before end pos=${_position.inMilliseconds}ms duration=${duration.inMilliseconds}ms',
      );
    }
    return nearEnd;
  }

  void _syncQueueWithLibrary({String? previousCurrentId}) {
    _activeQueueIds = _activeQueueIds
        .where((key) => _findMusicIndexByQueueKey(key) != -1)
        .map((key) => _queueKey(_musicList[_findMusicIndexByQueueKey(key)]))
        .toList();
    if (_activeQueueIds.isEmpty) {
      _activeQueueIds = _musicList.map(_queueKey).toList();
    }

    final current = currentMusic;
    final currentId = current == null ? previousCurrentId : _queueKey(current);
    if (currentId != null) {
      final actualIndex = _findMusicIndexByQueueKey(currentId);
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
            .where((id) => _findMusicIndexByQueueKey(id) != -1)
            .map((id) => _queueKey(_musicList[_findMusicIndexByQueueKey(id)]))
            .toList() ??
        [];
    _activeQueueIds =
        queueIds.isNotEmpty ? queueIds : _musicList.map(_queueKey).toList();

    _currentPlaylistId = state['playlistId'] as String?;
    _isShuffle = state['shuffle'] == true;
    _isRepeatOne = state['repeatOne'] == true;
    _isRepeatAll = state['repeatAll'] != false;
    _shouldResumeCurrentTrack = state['shouldResumeCurrentTrack'] != false;

    final currentId = state['currentMusicKey']?.toString() ??
        state['currentMusicId']?.toString();
    if (currentId != null) {
      final restoredIndex = _findMusicIndexByQueueKey(currentId);
      if (restoredIndex != -1) {
        _currentIndex = restoredIndex;
      }
    }

    _rebuildShuffledQueue();
    _hasRestoredPlayback = true;
    _pendingPlaybackState = null;

    try {
      final restoredTrack = _musicList[_currentIndex];
      final restoredKey = _queueKey(restoredTrack);
      final positionMs = state['positionMs'] as int? ?? 0;
      final wasPlaying = state['wasPlaying'] == true;
      if (_isVideoTrack(restoredTrack) && !wasPlaying) {
        _videoPlayback.setCurrentTrack(restoredTrack);
        _duration = restoredTrack.duration ?? Duration.zero;
        _durationNotifier.value = _duration;
        _position = Duration(milliseconds: max(0, positionMs));
        _positionNotifier.value = _position;
        _resumeTrackId = restoredKey;
        _resumePosition = _position;
        _shouldResumeCurrentTrack = _position > Duration.zero;
        await _audioHandler.updateNowPlaying(
          restoredTrack,
          playing: false,
          position: _position,
          duration: restoredTrack.duration,
        );
        _syncExternalPlaybackState(playing: false, position: _position);
        notifyListeners();
        return;
      }

      await _openTrackMedia(restoredTrack);
      _openedMusicId = restoredKey;
      if (positionMs > 0) {
        final restoredPosition = Duration(milliseconds: positionMs);
        await _seekCurrentBackend(restoredPosition);
        _position = restoredPosition;
        _positionNotifier.value = restoredPosition;
        _resumeTrackId = restoredKey;
        _resumePosition = restoredPosition;
      } else {
        _resumeTrackId = restoredKey;
        _resumePosition = Duration.zero;
        _shouldResumeCurrentTrack = false;
      }
      if (wasPlaying) {
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
    _savePlaybackTimer?.cancel();
    _songGapCountdownTimer?.cancel();
    _nativeAudioProgressTimer?.cancel();
    unawaited(_saveAudioEffectsSettings());
    _savePlaybackState();
    for (final subscription in _playerSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_clearNowPlaying());
    if (!kIsWeb && Platform.isWindows) {
      unawaited(_windowsMediaControlChannel.invokeMethod('setOwnership', {
        'active': false,
        'playing': false,
      }).catchError((_) {}));
      _windowsMediaControlChannel.setMethodCallHandler(null);
    }
    _videoPlayback.dispose();
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
    _songGapRemainingNotifier.dispose();
    _playingNotifier.dispose();
    super.dispose();
  }
}

class _RecommendedTrack {
  final Music music;
  final double score;

  const _RecommendedTrack(this.music, this.score);
}

class LibraryMiniStat {
  final String label;
  final String value;
  final double ratio;

  const LibraryMiniStat(this.label, this.value, this.ratio);
}

class LibraryStatsDashboard {
  final int totalRecords;
  final int musicRecords;
  final int videoRecords;
  final int likedRecords;
  final int playedRecords;
  final int playlistCount;
  final int totalPlays;
  final Duration totalDuration;
  final int genreCount;
  final int artistCount;
  final int albumCount;
  final int yearCount;
  final int aiCandidates;
  final StatsRankItem topGenre;
  final StatsRankItem topArtist;
  final List<StatsSlice> mediaSlices;
  final List<StatsSlice> likedSlices;
  final List<StatsSlice> playedSlices;
  final List<StatsRankItem> genreRanks;
  final List<StatsRankItem> artistRanks;
  final List<StatsRankItem> albumRanks;
  final List<StatsRankItem> yearRanks;
  final List<StatsRankItem> playlistRanks;
  final List<StatsRankItem> topPlayedTracks;
  final List<StatsRankItem> recentlyPlayed;
  final List<StatsRankItem> earlyListened;
  final List<RecommendationSignalStat> recommendationSignals;

  const LibraryStatsDashboard({
    required this.totalRecords,
    required this.musicRecords,
    required this.videoRecords,
    required this.likedRecords,
    required this.playedRecords,
    required this.playlistCount,
    required this.totalPlays,
    required this.totalDuration,
    required this.genreCount,
    required this.artistCount,
    required this.albumCount,
    required this.yearCount,
    required this.aiCandidates,
    required this.topGenre,
    required this.topArtist,
    required this.mediaSlices,
    required this.likedSlices,
    required this.playedSlices,
    required this.genreRanks,
    required this.artistRanks,
    required this.albumRanks,
    required this.yearRanks,
    required this.playlistRanks,
    required this.topPlayedTracks,
    required this.recentlyPlayed,
    required this.earlyListened,
    required this.recommendationSignals,
  });
}

class StatsSlice {
  final String label;
  final int value;

  const StatsSlice(this.label, this.value);
}

class StatsRankItem {
  final String label;
  final int value;
  final double ratio;
  final String? subtitle;

  const StatsRankItem(
    this.label,
    this.value,
    this.ratio, {
    this.subtitle,
  });
}

class RecommendationSignalStat {
  final String label;
  final int value;
  final double ratio;

  const RecommendationSignalStat(this.label, this.value, this.ratio);
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
