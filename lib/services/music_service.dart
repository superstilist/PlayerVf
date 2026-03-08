import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Playlist;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_model.dart';
import '../models/playlist_model.dart';
import 'music_scanner_service.dart';

class MusicService extends ChangeNotifier {
  // --- Core State ---
  List<Music> _musicList = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late final Player _player;
  
  // Separate ValueNotifiers for playback state to avoid full rebuilds
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationNotifier = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> _playingNotifier = ValueNotifier(false);
  
  // Track initialization state
  bool _isInitialized = false;
  
  // Performance State
  DateTime _lastPositionUpdate = DateTime.now();
  Timer? _saveSettingsTimer;
  List<int> _queue = [];
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

  // Audio Effects
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

  static const List<int> _eqFreqs = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
  static const Map<String, List<double>> _eqPresets = {
    'Normal':    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    'Pop':       [-1, 2, 4, 5, 4, 2, 0, -1, -2, -3],
    'Rock':      [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
    'Jazz':      [3, 2, 1, 2, -2, -2, 0, 1, 2, 3],
    'Classical': [4, 3, 2, 1, -1, -1, 0, 2, 3, 4],
    'Bass Boost':[6, 5, 4, 3, 1, 0, 0, 0, 0, 0],
    'Treble Boost':[0, 0, 0, 0, 0, 1, 2, 4, 5, 6],
    'Electronic':[-2, 0, 2, 4, 5, 4, 2, 0, -1, -2],
    'Hip Hop':   [5, 4, 3, 1, -1, -2, 0, 1, 2, 3],
    'Acoustic':  [3, 2, 1, 1, 2, 2, 3, 3, 2, 2],
  };

  MusicService() {
    _player = Player();
    _initPlayer();
    _initializeAsync();
  }

  // Async initialization - runs separately from constructor
  Future<void> _initializeAsync() async {
    // Load settings and stats without triggering UI rebuilds
    await _loadSettingsAsync();
    _isInitialized = true;
    // Only notify after initial load is complete
    notifyListeners();
  }

  void _initPlayer() {
    _player.stream.position.listen((pos) {
      final now = DateTime.now();
      if (now.difference(_lastPositionUpdate).inMilliseconds > 500) {
        _position = pos;
        _positionNotifier.value = pos;
        _lastPositionUpdate = now;
      }
    });
    _player.stream.duration.listen((dur) { 
      _duration = dur; 
      _durationNotifier.value = dur;
    });
    _player.stream.completed.listen((done) { if (done) next(); });
    _player.stream.playing.listen((state) { 
      _isPlaying = state; 
      _playingNotifier.value = state;
    });
  }

  // --- Getters ---
  List<Music> get musicList => _musicList;
  Music? get currentMusic => _musicList.isNotEmpty && _currentIndex < _musicList.length ? _musicList[_currentIndex] : null;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  
  // ValueNotifiers for efficient UI updates without full rebuilds
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

  List<double> get currentEqBandValues {
    if (_useSongSpecificSettings && currentMusic != null) {
      final s = _songSettings[currentMusic!.id];
      if (s != null && s['eq'] != null) return List<double>.from(s['eq'].map((e) => (e as num).toDouble()));
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
    if (index >= 0 && index < _musicList.length) { _currentIndex = index; notifyListeners(); }
  }
  set currentPlaylistId(String? id) { _currentPlaylistId = id; notifyListeners(); }

  // --- Audio Effects Engine ---
  void setEffectsEnabled(bool v) { _isEffectsEnabled = v; _scheduleUpdate(); notifyListeners(); }
  void setEqualizerEnabled(bool v) { _isEqualizerEnabled = v; _scheduleUpdate(); notifyListeners(); }
  void setUseSongSpecificSettings(bool v) { _useSongSpecificSettings = v; _scheduleUpdate(); notifyListeners(); }
  void setPitch(double v) { _pitch = v; _scheduleUpdate(); notifyListeners(); }
  void setSpeed(double v) { _speed = v; _scheduleUpdate(); notifyListeners(); }
  void setReverb(double v) { _reverb = v; _scheduleUpdate(); notifyListeners(); }

  void setEqualizerBand(int band, double val) {
    val = double.parse(val.toStringAsFixed(1));
    if (_useSongSpecificSettings && currentMusic != null) {
      final id = currentMusic!.id;
      _songSettings[id] ??= {'eq': List.from(_globalEqValues)};
      _songSettings[id]['eq'][band] = val;
    } else {
      _globalEqValues[band] = val;
      _currentPreset = 'Custom';
    }
    _scheduleUpdate(); _saveDebounced(); notifyListeners();
  }

  void setEqualizerPreset(String preset) {
    _currentPreset = preset;
    if (_eqPresets.containsKey(preset)) {
      final values = List<double>.from(_eqPresets[preset]!);
      if (_useSongSpecificSettings && currentMusic != null) {
        _songSettings[currentMusic!.id] ??= {};
        _songSettings[currentMusic!.id]['eq'] = values;
      } else { _globalEqValues = values; }
    }
    _scheduleUpdate(); _saveDebounced(); notifyListeners();
  }

  void _scheduleUpdate() async {
    if (_isUpdatingEffects) { _hasPendingUpdate = true; return; }
    _isUpdatingEffects = true; _hasPendingUpdate = false;
    try {
      final native = _player.platform;
      if (native is NativePlayer) {
        String af = '';
        if (_isEffectsEnabled) {
          if (_isEqualizerEnabled) {
            final v = currentEqBandValues;
            af = 'equalizer=f=${_eqFreqs[0]}:g=${v[0]}';
            for (int i=1; i<10; i++) { af += ',equalizer=f=${_eqFreqs[i]}:g=${v[i]}'; }
          }
          if (_reverb > 0) {
            // Realistic and strong reverb chain:
            // 1. aecho: Simulates initial reflections (pre-delay)
            // 2. freeverb: High-quality Schroeder-Moorer reverb
            // 3. extrastereo: Increases the spatial feeling
            final preDelay = 'aecho=0.8:0.88:${(_reverb * 60).toInt() + 20}:${_reverb * 0.3}';
            final reverb = 'freeverb=roomsize=${0.7 + (_reverb * 0.25)}:damp=${0.2 + (1.0 - _reverb) * 0.5}:wet=${_reverb * 0.8}:dry=${1.0 - (_reverb * 0.5)}:width=1.0';
            final spatial = 'extrastereo=m=${1.0 + _reverb * 1.5}';
            
            af += (af.isEmpty ? '' : ',') + '$preDelay,$reverb,$spatial';
          }
        }
        
        // Use 'af' property for filters
        if (af != _lastAppliedAf) { 
          await native.setProperty('af', af); 
          _lastAppliedAf = af; 
        }
        
        // Use direct properties for speed and pitch if available, or fall back to native setProperty
        await _player.setRate(_isEffectsEnabled ? _speed : 1.0);
        await _player.setPitch(_isEffectsEnabled ? _pitch : 1.0);
      }
    } catch (e) {
      debugPrint("Error updating effects: $e");
    } finally {
      _isUpdatingEffects = false;
      if (_hasPendingUpdate) _scheduleUpdate();
    }
  }

  List<String>? _lastUsedPaths;

  // --- Core Methods ---
  Future<void> play() async {
    if (_musicList.isEmpty) return;
    try {
      await _player.open(Media(_musicList[_currentIndex].filePath));
      _musicList[_currentIndex].playCount++;
      _musicList[_currentIndex].lastPlayed = DateTime.now();
      
      // Reset effects state for new track
      _lastAppliedAf = null; 
      _scheduleUpdate();
      
      // Save stats in background
      _saveStats();
      // Notify listeners for music change
      notifyListeners();
    } catch (e) { debugPrint('Play Error: $e'); }
  }

  void togglePlayPause() { _player.playOrPause(); }
  void seekTo(Duration p) { _player.seek(p); }

  void next() {
    if (_musicList.isEmpty) return;
    if (_isShuffle && _queue.isNotEmpty) {
      int idx = _queue.indexOf(_currentIndex);
      _currentIndex = _queue[(idx + 1) % _queue.length];
    } else { _currentIndex = (_currentIndex + 1) % _musicList.length; }
    play();
  }

  void previous() {
    if (_musicList.isEmpty) return;
    if (_position.inSeconds > 3) { seekTo(Duration.zero); return; }
    if (_isShuffle && _queue.isNotEmpty) {
      int idx = _queue.indexOf(_currentIndex);
      _currentIndex = _queue[idx > 0 ? idx - 1 : _queue.length - 1];
    } else { _currentIndex = _currentIndex > 0 ? _currentIndex - 1 : _musicList.length - 1; }
    play();
  }

  void toggleShuffle() { _isShuffle = !_isShuffle; if (_isShuffle) _generateShuffleQueue(); notifyListeners(); }
  void toggleRepeatMode() {
    if (_isRepeatAll && !_isRepeatOne) { _isRepeatAll = false; _isRepeatOne = true; }
    else if (!_isRepeatAll && _isRepeatOne) { _isRepeatOne = false; }
    else { _isRepeatAll = true; _isRepeatOne = false; }
    notifyListeners();
  }

  void _generateShuffleQueue() {
    _queue = List.generate(_musicList.length, (i) => i);
    _queue.remove(_currentIndex); _queue.shuffle(); _queue.insert(0, _currentIndex);
  }

  // --- Library Management ---
  Future<void> loadSystemMusic({List<String>? customPaths, bool clearExisting = true}) async {
    if (_isLoadingSystemMusic) return;

    final hasPermission = await MusicScannerService.checkPermissions();
    if (!hasPermission) return;

    _isLoadingSystemMusic = true;
    if (customPaths != null) _lastUsedPaths = customPaths;
    
    if (clearExisting) {
      _musicList = [];
      _systemMusicCount = 0;
    }
    notifyListeners();
    
    // Use a timer to throttle notifyListeners during scanning
    Timer? throttleTimer;
    
    await MusicScannerService.startScanning(
      customPaths: customPaths ?? _lastUsedPaths,
      onBatchUpdate: (batch) {
        bool changed = false;
        for (var m in batch) {
          if (!_musicList.any((existing) => existing.filePath == m.filePath)) {
            _musicList.add(m);
            changed = true;
          }
        }
        
        if (changed) {
          _systemMusicCount = _musicList.length;
          // Throttle UI updates
          if (throttleTimer == null || !throttleTimer!.isActive) {
            notifyListeners();
            throttleTimer = Timer(const Duration(milliseconds: 500), () {});
          }
        }
      }
    );

    throttleTimer?.cancel();
    
    // Load stats and favorites in background
    await _loadStatsAsync();
    await _loadFavoritesAsync();
    
    _isLoadingSystemMusic = false; 
    _generateShuffleQueue(); 
    // Refresh playlists only when explicitly loading
    _refreshSystemPlaylistsInternal();
    notifyListeners();
  }

  Future<void> clearCache() async {
    _musicList = []; 
    _systemMusicCount = 0;
    notifyListeners(); 
    await loadSystemMusic(customPaths: _lastUsedPaths);
  }

  void deleteMusic(int idx) {
    if (idx >= 0 && idx < _musicList.length) {
      _musicList.removeAt(idx);
      if (_currentIndex >= _musicList.length) _currentIndex = max(0, _musicList.length - 1);
      notifyListeners();
    }
  }

  Future<void> updateMusicMetadata(String id, String t, String a, String al, String g) async {
    int idx = _musicList.indexWhere((m) => m.id == id);
    if (idx != -1) {
      final old = _musicList[idx];
      final neu = Music(id: old.id, title: t, artist: a, album: al, genre: g, filePath: old.filePath, coverPath: old.coverPath, duration: old.duration, isFavorite: old.isFavorite, playCount: old.playCount, lastPlayed: old.lastPlayed);
      _musicList[idx] = neu; notifyListeners();
    }
  }

  void _refreshSystemPlaylistsInternal() {
    if (_musicList.isEmpty) return;
    final history = List<Music>.from(_musicList)
      ..where((m) => m.lastPlayed != null).toList()
      ..sort((a, b) => (b.lastPlayed ?? DateTime(0)).compareTo(a.lastPlayed ?? DateTime(0)));
    _cachedEarlyListened = history.take(10).toList();
    final topPlayed = List<Music>.from(_musicList)
      ..where((m) => m.playCount > 0).toList()
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
    for (var m in _musicList) {
      if (m.playCount > 0) genreScores[m.genre] = (genreScores[m.genre] ?? 0) + m.playCount;
    }
    final sortedGenres = genreScores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topGenres = sortedGenres.take(3).map((e) => e.key).toList();
    final Set<Music> mix = {};
    if (topGenres.isNotEmpty) {
      final genrePool = _musicList.where((m) => topGenres.contains(m.genre)).toList()..shuffle();
      mix.addAll(genrePool.take(10));
    }
    final discoveryPool = List<Music>.from(_musicList)..shuffle();
    mix.addAll(discoveryPool.take(15));
    return mix.toList()..shuffle();
  }

  Future<void> createPlaylist(String name) async {
    _playlists.add(Playlist(id: DateTime.now().millisecondsSinceEpoch.toString(), name: name, musicIds: [], createdAt: DateTime.now(), updatedAt: DateTime.now()));
    await _savePlaylists(); notifyListeners();
  }
  void deletePlaylist(String id) { _playlists.removeWhere((p) => p.id == id); _savePlaylists(); notifyListeners(); }
  void addMusicToPlaylist(String plId, String mId) {
    final pl = _playlists.firstWhere((p) => p.id == plId);
    if (!pl.musicIds.contains(mId)) { pl.musicIds.add(mId); _savePlaylists(); notifyListeners(); }
  }
  void removeMusicFromPlaylist(String plId, String mId) {
    int idx = _playlists.indexWhere((p) => p.id == plId);
    if (idx != -1) { _playlists[idx].musicIds.remove(mId); _savePlaylists(); notifyListeners(); }
  }
  void playPlaylist(String id) {
    final list = getMusicListForPlaylist(id);
    if (list.isNotEmpty) {
      _currentPlaylistId = id;
      _currentIndex = _musicList.indexWhere((m) => m.id == list.first.id);
      if (_isShuffle) _generateShuffleQueue();
      play();
    }
  }
  List<Music> getMusicListForPlaylist(String id) {
    if (id == 'favorites') return favoriteMusicList;
    if (id == 'most_listened') return _cachedMostListened;
    if (id == 'early_listened') return _cachedEarlyListened;
    if (id == 'daily_mix') return _cachedDailyMix;
    final pl = _playlists.firstWhere((p) => p.id == id, orElse: () => Playlist(id: '', name: '', createdAt: DateTime.now(), updatedAt: DateTime.now()));
    return _musicList.where((m) => pl.musicIds.contains(m.id)).toList();
  }

  // --- Async Background Loading ---
  Future<void> _loadSettingsAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEffectsEnabled = prefs.getBool('master_eff') ?? true;
      final eqList = prefs.getStringList('glob_eq');
      if (eqList != null) _globalEqValues = eqList.map((e) => double.tryParse(e) ?? 0.0).toList();
      
      // Load playlists
      final dir = await getApplicationDocumentsDirectory();
      final plFile = File('${dir.path}/playlists.json');
      if (await plFile.exists()) {
        final data = jsonDecode(await plFile.readAsString()) as List;
        _playlists = data.map((j) => Playlist.fromJson(j)).toList();
      }
      
      // Load stats (but don't apply yet - music list may not be loaded)
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
        for (var item in data) {
          int idx = _musicList.indexWhere((m) => m.id == item['id']);
          if (idx != -1) {
            _musicList[idx] = Music.fromBase(_musicList[idx], item['playCount'] ?? 0, item['lastPlayed'] != null ? DateTime.fromMillisecondsSinceEpoch(item['lastPlayed']) : null);
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
        for (var m in _musicList) m.isFavorite = ids.contains(m.id);
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
    }
  }

  void _saveDebounced() {
    _saveSettingsTimer?.cancel();
    _saveSettingsTimer = Timer(const Duration(seconds: 2), () => _saveAudioEffectsSettings());
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

  Future<void> toggleFavorite(String id) async {
    int idx = _musicList.indexWhere((m) => m.id == id);
    if (idx != -1) {
      final old = _musicList[idx];
      // Create a new instance to ensure change detection works correctly
      _musicList[idx] = Music(
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
        final ids = _musicList.where((m) => m.isFavorite).map((m) => m.id).toList();
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
      await file.writeAsString(jsonEncode(_playlists.map((p) => p.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving playlists: $e');
    }
  }

  Future<void> _saveStats() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/music_stats.json');
      await file.writeAsString(jsonEncode(_musicList.map((m) => m.toJson()).toList()));
    } catch (e) {
      debugPrint('Error saving stats: $e');
    }
  }

  List<int> getEqualizerFrequencies() => _eqFreqs;
  List<String> getEqualizerPresets() => _eqPresets.keys.toList();
  @override
  void dispose() { 
    _player.dispose(); 
    _saveSettingsTimer?.cancel();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    _playingNotifier.dispose();
    super.dispose(); 
  }

  // Check if a music item is marked as favorite
  bool isFavorite(String id) {
    try {
      final music = _musicList.firstWhere((m) => m.id == id);
      return music.isFavorite;
    } catch (e) {
      return false;
    }
  }
}
