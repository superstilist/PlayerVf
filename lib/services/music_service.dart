import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/music_model.dart';
import '../models/playlist_model.dart';
import 'music_scanner_service.dart';

class MusicService extends ChangeNotifier with WidgetsBindingObserver {
  static const String _playbackStateKey = 'playback_state';
  static const String _rememberPlaybackKey = 'remember_playback_enabled';

  List<Music> _musicList = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final Player _player;

  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _playingNotifier = ValueNotifier(false);

  bool _isInitialized = false;
  DateTime _lastPositionUpdate = DateTime.now();
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
  Map<String, dynamic>? _pendingPlaybackState;
  String? _openedMusicId;
  String? _resumeTrackId;
  Duration _resumePosition = Duration.zero;
  bool _shouldResumeCurrentTrack = false;

  bool _isEffectsEnabled = true;
  bool _isEqualizerEnabled = false;
  List<double> _globalEqValues = List.filled(10, 0.0);
  String _currentPreset = 'Normal';
  double _pitch = 1.0;
  double _speed = 1.0;
  double _reverb = 0.0;
  Map<String, dynamic> _songSettings = {};
  bool _useSongSpecificSettings = false;

  String? _lastAppliedAf;
  bool _isUpdatingEffects = false;
  bool _hasPendingUpdate = false;
  bool _supportsPitchControl = true;
  List<String>? _lastUsedPaths;

  static const List<int> _eqFreqs = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
  static const Map<String, List<double>> _eqPresets = {
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
  };

  MusicService() {
    WidgetsBinding.instance.addObserver(this);
    _player = Player();
    _initPlayer();
    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    await _loadSettingsAsync();
    _isInitialized = true;
    notifyListeners();
  }

  void _initPlayer() {
    _player.stream.position.listen((pos) {
      final now = DateTime.now();
      if (now.difference(_lastPositionUpdate).inMilliseconds > 500) {
        _position = pos;
        _positionNotifier.value = pos;
        _lastPositionUpdate = now;
        _savePlaybackDebounced();
        notifyListeners();
      }
    });

    _player.stream.duration.listen((dur) {
      _duration = dur;
      _durationNotifier.value = dur;
    });

    _player.stream.completed.listen((done) {
      if (done) {
        _handleTrackCompleted();
      }
    });

    _player.stream.playing.listen((state) {
      _isPlaying = state;
      _playingNotifier.value = state;
      _savePlaybackDebounced();
    });
  }

  List<Music> get musicList => _musicList;
  Music? get currentMusic => _musicList.isNotEmpty && _currentIndex < _musicList.length ? _musicList[_currentIndex] : null;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  ValueNotifier<Duration> get positionNotifier => _positionNotifier;
  ValueNotifier<Duration> get durationNotifier => _durationNotifier;
  ValueNotifier<bool> get playingNotifier => _playingNotifier;
  bool get isLoadingSystemMusic => _isLoadingSystemMusic;
  int get systemMusicCount => _systemMusicCount;
  List<Playlist> get playlists => _playlists;
  bool get isShuffle => _isShuffle;
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
  List<Music> get queueMusicList => _resolveMusicIds(_playbackOrderIds());
  int get currentQueuePosition {
    final current = currentMusic;
    if (current == null) return -1;
    return _playbackOrderIds().indexOf(current.id);
  }

  List<double> get currentEqBandValues {
    if (_useSongSpecificSettings && currentMusic != null) {
      final song = _songSettings[currentMusic!.id];
      if (song != null && song['eq'] != null) {
        return List<double>.from(song['eq'].map((e) => (e as num).toDouble()));
      }
    }
    return _globalEqValues;
  }

  List<Music> get favoriteMusicList => _musicList.where((m) => m.isFavorite).toList();
  List<Playlist> get systemPlaylists => [
    Playlist(id: 'favorites', name: 'Favorites', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    Playlist(id: 'most_listened', name: 'Most Listened', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    Playlist(id: 'early_listened', name: 'Early Listened', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    Playlist(id: 'daily_mix', name: 'Daily Mix', createdAt: DateTime.now(), updatedAt: DateTime.now()),
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
    _scheduleUpdate();
    _saveDebounced();
  }

  void setEqualizerEnabled(bool value) {
    _isEqualizerEnabled = value;
    if (value) _isEffectsEnabled = true;
    notifyListeners();
    _scheduleUpdate();
    _saveDebounced();
  }

  void setUseSongSpecificSettings(bool value) {
    _useSongSpecificSettings = value;
    notifyListeners();
    _scheduleUpdate();
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
    value = double.parse(value.toStringAsFixed(1));
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
    _scheduleUpdate();
    _saveDebounced();
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
    _scheduleUpdate();
    _saveDebounced();
  }

  void resetEqualizer() {
    _currentPreset = 'Normal';
    if (_useSongSpecificSettings && currentMusic != null) {
      _songSettings[currentMusic!.id] ??= {};
      _songSettings[currentMusic!.id]['eq'] = List<double>.from(_eqPresets['Normal']!);
    } else {
      _globalEqValues = List<double>.from(_eqPresets['Normal']!);
    }
    _isEqualizerEnabled = false;
    notifyListeners();
    _scheduleUpdate();
    _saveDebounced();
  }

  void resetAudioEffects() {
    _isEffectsEnabled = true;
    _isEqualizerEnabled = false;
    _currentPreset = 'Normal';
    _pitch = 1.0;
    _speed = 1.0;
    _reverb = 0.0;
    if (_useSongSpecificSettings && currentMusic != null) {
      _songSettings.remove(currentMusic!.id);
    }
    _globalEqValues = List<double>.from(_eqPresets['Normal']!);
    notifyListeners();
    _scheduleUpdate();
    _saveDebounced();
  }

  void _scheduleUpdate() async {
    if (_isUpdatingEffects) {
      _hasPendingUpdate = true;
      return;
    }

    _isUpdatingEffects = true;
    _hasPendingUpdate = false;
    try {
      final native = _player.platform;
      if (native is NativePlayer) {
        String af = '';
        if (_isEffectsEnabled) {
          if (_isEqualizerEnabled) {
            final values = currentEqBandValues;
            af = 'equalizer=f=${_eqFreqs[0]}:g=${values[0]}';
            for (int i = 1; i < 10; i++) {
              af += ',equalizer=f=${_eqFreqs[i]}:g=${values[i]}';
            }
          }
          if (_reverb > 0) {
            final preDelay = 'aecho=0.8:0.88:${(_reverb * 60).toInt() + 20}:${_reverb * 0.3}';
            final reverb = 'freeverb=roomsize=${0.7 + (_reverb * 0.25)}:damp=${0.2 + (1.0 - _reverb) * 0.5}:wet=${_reverb * 0.8}:dry=${1.0 - (_reverb * 0.5)}:width=1.0';
            final spatial = 'extrastereo=m=${1.0 + _reverb * 1.5}';
            af += '${af.isEmpty ? '' : ','}$preDelay,$reverb,$spatial';
          }
        }

        if (af != _lastAppliedAf) {
          await native.setProperty('af', af);
          _lastAppliedAf = af;
        }

        await _player.setRate(_isEffectsEnabled ? _speed : 1.0);
        if (_supportsPitchControl) {
          try {
            await _player.setPitch(_isEffectsEnabled ? _pitch : 1.0);
          } catch (e) {
            _supportsPitchControl = false;
            debugPrint('Pitch control is not supported on this platform: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error updating effects: $e');
    } finally {
      _isUpdatingEffects = false;
      if (_hasPendingUpdate) _scheduleUpdate();
    }
  }

  Future<void> _fadeVolume(double start, double end, Duration duration) async {
    const steps = 15;
    final interval = duration.inMilliseconds ~/ steps;
    final delta = (end - start) / steps;
    
    for (int i = 0; i <= steps; i++) {
      final vol = (start + delta * i).clamp(0.0, 1.0);
      _player.setVolume(vol * 100);
      await Future.delayed(Duration(milliseconds: interval));
    }
  }

  Future<void> play() async {
    if (_musicList.isEmpty) return;
    _ensureQueueInitialized();
    try {
      final track = _musicList[_currentIndex];
      final trackId = track.id;

      if (_openedMusicId == trackId) {
        if (_shouldResumeCurrentTrack) {
          await _applyResumePositionIfNeeded(trackId);
        }
        await _player.play();
        _musicList[_currentIndex].lastPlayed = DateTime.now();
        _shouldResumeCurrentTrack = false;
        _saveStats();
        _savePlaybackDebounced();
        notifyListeners();
        return;
      }

      // Smooth fade out before opening new track
      if (_isPlaying) await _fadeVolume(1.0, 0.0, const Duration(milliseconds: 250));

      final startPosition =
          (_shouldResumeCurrentTrack && _resumeTrackId == trackId) ? _resumePosition : Duration.zero;
      await _player.open(Media(track.filePath), play: false);
      _openedMusicId = trackId;

      if (startPosition > Duration.zero) {
        await _player.seek(startPosition);
        _position = startPosition;
        _positionNotifier.value = startPosition;
      } else {
        _position = Duration.zero;
        _positionNotifier.value = Duration.zero;
      }

      if (_shouldResumeCurrentTrack) {
        await _applyResumePositionIfNeeded(trackId);
      }
      
      _player.setVolume(0);
      await _player.play();
      _fadeVolume(0.0, 1.0, const Duration(milliseconds: 350));

      track.playCount++;
      track.lastPlayed = DateTime.now();
      _resumeTrackId = trackId;
      _resumePosition = _position;
      _shouldResumeCurrentTrack = false;
      _lastAppliedAf = null;
      _scheduleUpdate();
      _saveStats();
      _savePlaybackDebounced();
      notifyListeners();
    } catch (e) {
      debugPrint('Play Error: $e');
    }
  }

  void togglePlayPause() {
    _togglePlayPauseInternal();
  }

  Future<void> _togglePlayPauseInternal() async {
    if (!_isPlaying && currentMusic != null) {
      if (_shouldResumeCurrentTrack) {
        await _applyResumePositionIfNeeded(currentMusic!.id);
      }
      _shouldResumeCurrentTrack = false;
      _player.setVolume(0);
      await _player.play();
      _fadeVolume(0.0, 1.0, const Duration(milliseconds: 250));
    } else if (_isPlaying && currentMusic != null) {
      _resumeTrackId = currentMusic!.id;
      _resumePosition = _position;
      _shouldResumeCurrentTrack = true;
      await _fadeVolume(1.0, 0.0, const Duration(milliseconds: 200));
      await _player.pause();
      _player.setVolume(100); // Reset for next time
    } else {
      _player.playOrPause();
    }
  }

  void seekTo(Duration position) {
    _player.seek(position);
    _position = position;
    _positionNotifier.value = position;
    _resumeTrackId = currentMusic?.id;
    _resumePosition = position;
    _shouldResumeCurrentTrack = position > Duration.zero;
    _savePlaybackDebounced();
    notifyListeners();
  }

  void next() {
    _clearResumeState(keepOpenedTrack: false);
    if (_moveInQueue(1)) {
      play();
    }
  }

  void previous() {
    if (_musicList.isEmpty) return;
    if (_position.inSeconds > 3) {
      seekTo(Duration.zero);
      return;
    }
    _clearResumeState(keepOpenedTrack: false);
    if (_moveInQueue(-1)) {
      play();
    }
  }

  void toggleShuffle() {
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

  Future<void> loadSystemMusic({List<String>? customPaths, bool clearExisting = true}) async {
    if (_isLoadingSystemMusic) return;

    final hasPermission = await MusicScannerService.checkPermissions();
    if (!hasPermission) return;

    _isLoadingSystemMusic = true;
    if (customPaths != null) _lastUsedPaths = customPaths;

    final previousCurrentId = currentMusic?.id;
    if (clearExisting) {
      _musicList = [];
      _systemMusicCount = 0;
    }
    notifyListeners();

    Timer? throttleTimer;

    await MusicScannerService.startScanning(
      customPaths: customPaths ?? _lastUsedPaths,
      onBatchUpdate: (batch) {
        bool changed = false;
        for (final music in batch) {
          if (!_musicList.any((existing) => existing.filePath == music.filePath)) {
            _musicList.add(music);
            changed = true;
          }
        }

        if (changed) {
          _systemMusicCount = _musicList.length;
          if (throttleTimer == null || !throttleTimer!.isActive) {
            notifyListeners();
            throttleTimer = Timer(const Duration(milliseconds: 500), () {});
          }
        }
      },
    );

    throttleTimer?.cancel();

    await _loadStatsAsync();
    await _loadFavoritesAsync();

    _isLoadingSystemMusic = false;
    _syncQueueWithLibrary(previousCurrentId: previousCurrentId);
    _refreshSystemPlaylistsInternal();
    await _restorePlaybackStateIfNeeded();
    notifyListeners();
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
      notifyListeners();
    }
  }

  Future<void> updateMusicMetadata(String id, String title, String artist, String album, String genre) async {
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
    }
  }

  void _refreshSystemPlaylistsInternal() {
    if (_musicList.isEmpty) return;

    final history = _musicList.where((music) => music.lastPlayed != null).toList()
      ..sort((a, b) => (b.lastPlayed ?? DateTime(0)).compareTo(a.lastPlayed ?? DateTime(0)));
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
        genreScores[music.genre] = (genreScores[music.genre] ?? 0) + music.playCount;
      }
    }

    final sortedGenres = genreScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = sortedGenres.take(3).map((entry) => entry.key).toList();

    final mix = <Music>{};
    if (topGenres.isNotEmpty) {
      final genrePool = _musicList.where((music) => topGenres.contains(music.genre)).toList()..shuffle();
      mix.addAll(genrePool.take(10));
    }

    final discoveryPool = List<Music>.from(_musicList)..shuffle();
    mix.addAll(discoveryPool.take(15));
    return mix.toList()..shuffle();
  }

  Future<void> createPlaylist(String name) async {
    _playlists.add(Playlist(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, musicIds: [], createdAt: DateTime.now(), updatedAt: DateTime.now()));
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
      startQueue(list, startMusicId: list.first.id, playlistId: id);
      play();
    }
  }

  void playMusicFromQueue(List<Music> queue, Music target, {String? playlistId}) {
    startQueue(queue, startMusicId: target.id, playlistId: playlistId);
    play();
  }

  void startQueue(List<Music> queue, {String? startMusicId, String? playlistId}) {
    final ids = queue.map((music) => music.id).where((id) => _musicList.any((track) => track.id == id)).toList();
    if (ids.isEmpty) return;

    _activeQueueIds = ids;
    _currentPlaylistId = playlistId;
    final selectedId = startMusicId ?? ids.first;
    final actualIndex = _musicList.indexWhere((music) => music.id == selectedId);
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
    if (!_musicList.any((music) => music.id == musicId)) return;
    _ensureQueueInitialized();

    _activeQueueIds.remove(musicId);
    final currentId = currentMusic?.id;
    final insertIndex = currentId == null ? _activeQueueIds.length : _activeQueueIds.indexOf(currentId) + 1;
    final safeIndex = insertIndex.clamp(0, _activeQueueIds.length);
    _activeQueueIds.insert(safeIndex, musicId);
    _rebuildShuffledQueue();
    _savePlaybackDebounced();
    notifyListeners();
  }

  void removeFromQueue(String musicId) {
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
        play();
        return;
      }
    }

    _rebuildShuffledQueue();
    _savePlaybackDebounced();
    notifyListeners();
  }

  void moveQueueItem(int oldIndex, int newIndex) {
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
      orElse: () => Playlist(id: '', name: '', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );
    return _musicList.where((music) => playlist.musicIds.contains(music.id)).toList();
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
      _isEffectsEnabled = prefs.getBool('master_eff') ?? true;
      _rememberPlayback = prefs.getBool(_rememberPlaybackKey) ?? true;
      final eqList = prefs.getStringList('glob_eq');
      if (eqList != null) {
        _globalEqValues = eqList.map((entry) => double.tryParse(entry) ?? 0.0).toList();
      }

      final savedSongSettings = prefs.getString('song_eff_map');
      if (savedSongSettings != null && savedSongSettings.isNotEmpty) {
        _songSettings = Map<String, dynamic>.from(jsonDecode(savedSongSettings));
      }

      final savedPlayback = prefs.getString(_playbackStateKey);
      if (savedPlayback != null && savedPlayback.isNotEmpty) {
        _pendingPlaybackState = Map<String, dynamic>.from(jsonDecode(savedPlayback));
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
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_stats.json');
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString()) as List;
        for (final item in data) {
          final index = _musicList.indexWhere((music) => music.id == item['id']);
          if (index != -1) {
            _musicList[index] = Music.fromBase(
              _musicList[index],
              item['playCount'] ?? 0,
              item['lastPlayed'] != null ? DateTime.fromMillisecondsSinceEpoch(item['lastPlayed']) : null,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading stats: $e');
    }
  }

  Future<void> _loadFavoritesAsync() async {
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
    _saveSettingsTimer = Timer(const Duration(seconds: 2), _saveAudioEffectsSettings);
  }

  void _savePlaybackDebounced() {
    if (!_rememberPlayback) return;
    _savePlaybackTimer?.cancel();
    _savePlaybackTimer = Timer(const Duration(milliseconds: 800), _savePlaybackState);
  }

  Future<void> _saveAudioEffectsSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('master_eff', _isEffectsEnabled);
      await prefs.setString('song_eff_map', jsonEncode(_songSettings));
      await prefs.setStringList('glob_eq', _globalEqValues.map((e) => e.toString()).toList());
    } catch (e) {
      debugPrint('Error saving audio effects: $e');
    }
  }

  Future<void> _savePlaybackState() async {
    if (!_rememberPlayback) return;
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
    if (!_shouldResumeCurrentTrack || _resumeTrackId != trackId || _resumePosition <= Duration.zero) {
      return;
    }

    final currentDelta = (_position - _resumePosition).inMilliseconds.abs();
    if (currentDelta < 800) {
      return;
    }

    try {
      await _player.seek(_resumePosition);
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
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/favorites.json');
        final ids = _musicList.where((music) => music.isFavorite).map((music) => music.id).toList();
        await file.writeAsString(jsonEncode(ids));
      } catch (e) {
        debugPrint('Error saving favorite: $e');
      }
    }
  }

  Future<void> _savePlaylists() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/playlists.json');
      await file.writeAsString(jsonEncode(_playlists.map((playlist) => playlist.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving playlists: $e');
    }
  }

  Future<void> _saveStats() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_stats.json');
      await file.writeAsString(jsonEncode(_musicList.map((music) => music.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving stats: $e');
    }
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
      final loopIndex = _musicList.indexWhere((music) => music.id == order.last);
      if (loopIndex == -1) return false;
      _currentIndex = loopIndex;
      return true;
    }

    if (targetIndex >= order.length) {
      if (!_isRepeatAll) {
        _player.pause();
        _openedMusicId = currentMusic?.id;
        _resumeTrackId = currentMusic?.id;
        _resumePosition = Duration.zero;
        seekTo(Duration.zero);
        return false;
      }
      final loopIndex = _musicList.indexWhere((music) => music.id == order.first);
      if (loopIndex == -1) return false;
      _currentIndex = loopIndex;
      return true;
    }

    final actualIndex = _musicList.indexWhere((music) => music.id == order[targetIndex]);
    if (actualIndex == -1) return false;
    _currentIndex = actualIndex;
    return true;
  }

  void _handleTrackCompleted() {
    if (_isRepeatOne) {
      seekTo(Duration.zero);
      play();
      return;
    }

    if (_moveInQueue(1)) {
      play();
      return;
    }

    _player.pause();
    seekTo(Duration.zero);
    notifyListeners();
  }

  void _syncQueueWithLibrary({String? previousCurrentId}) {
    final validIds = _musicList.map((music) => music.id).toSet();
    _activeQueueIds = _activeQueueIds.where(validIds.contains).toList();
    if (_activeQueueIds.isEmpty) {
      _activeQueueIds = _musicList.map((music) => music.id).toList();
    }

    final currentId = currentMusic?.id ?? previousCurrentId;
    if (currentId != null) {
      final actualIndex = _musicList.indexWhere((music) => music.id == currentId);
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
    if (_hasRestoredPlayback || !_rememberPlayback || _pendingPlaybackState == null || _musicList.isEmpty) {
      return;
    }

    final state = _pendingPlaybackState!;
    final queueIds = (state['queueIds'] as List?)?.map((item) => item.toString()).where((id) => _musicList.any((music) => music.id == id)).toList() ?? [];
    _activeQueueIds = queueIds.isNotEmpty ? queueIds : _musicList.map((music) => music.id).toList();

    _currentPlaylistId = state['playlistId'] as String?;
    _isShuffle = state['shuffle'] == true;
    _isRepeatOne = state['repeatOne'] == true;
    _isRepeatAll = state['repeatAll'] != false;
    _shouldResumeCurrentTrack = state['shouldResumeCurrentTrack'] != false;

    final currentId = state['currentMusicId']?.toString();
    if (currentId != null) {
      final restoredIndex = _musicList.indexWhere((music) => music.id == currentId);
      if (restoredIndex != -1) {
        _currentIndex = restoredIndex;
      }
    }

    _rebuildShuffledQueue();
    _hasRestoredPlayback = true;
    _pendingPlaybackState = null;

    try {
      await _player.open(Media(_musicList[_currentIndex].filePath), play: false);
      _openedMusicId = _musicList[_currentIndex].id;
      final positionMs = state['positionMs'] as int? ?? 0;
      if (positionMs > 0) {
        final restoredPosition = Duration(milliseconds: positionMs);
        await _player.seek(restoredPosition);
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
        await _player.play();
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
    _savePlaybackState();
    _player.dispose();
    _saveSettingsTimer?.cancel();
    _savePlaybackTimer?.cancel();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _playingNotifier.dispose();
    super.dispose();
  }
}
