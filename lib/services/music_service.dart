import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/music_model.dart';
import '../models/cover_model.dart';
import '../models/playlist_model.dart';
import 'music_scanner_service.dart';

class MusicService extends ChangeNotifier {
  List<Music> _musicList = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  late AudioPlayer _audioPlayer;
  
  // Queue Management
  List<int> _queue = [];
  bool _isShuffle = false;
  
  // Scanning state
  bool _isLoadingSystemMusic = false;
  int _systemMusicCount = 0;
  String _currentScanPath = '';
  
  // Caching System Playlists
  List<Music> _cachedDailyMix = [];
  List<Music> _cachedMostListened = [];
  List<Music> _cachedEarlyListened = [];

  // Cache files
  static const String _favoritesCacheFile = 'favorites.json';
  static const String _playlistsCacheFile = 'playlists.json';
  static const String _statsCacheFile = 'music_stats.json';

  List<Playlist> _playlists = [];
  String? _currentPlaylistId;
  int _currentPlaylistIndex = 0;
  bool _isRepeatOne = false;
  bool _isRepeatAll = true;

  MusicService() {
    _audioPlayer = AudioPlayer();
    _initAudioPlayer();
    _loadFavoritesFromCache();
    _loadPlaylistsFromCache();
  }

  // Getters
  List<Music> get musicList => _musicList;
  int get currentIndex => _currentIndex;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isLoadingSystemMusic => _isLoadingSystemMusic;
  int get systemMusicCount => _systemMusicCount;
  String get currentScanPath => _currentScanPath;
  List<Playlist> get playlists => _playlists;
  bool get isShuffle => _isShuffle;
  bool get isRepeatOne => _isRepeatOne;
  bool get isRepeatAll => _isRepeatAll;

  String? get currentPlaylistId => _currentPlaylistId;
  set currentPlaylistId(String? id) {
    _currentPlaylistId = id;
    notifyListeners();
  }

  Music? get currentMusic => 
      _musicList.isNotEmpty && _currentIndex < _musicList.length 
          ? _musicList[_currentIndex] 
          : null;

  List<Music> get favoriteMusicList => _musicList.where((m) => m.isFavorite).toList();

  // System Playlists
  List<Playlist> get systemPlaylists {
    return [
      Playlist(id: 'favorites', name: 'Favorites', createdAt: DateTime.now(), updatedAt: DateTime.now()),
      Playlist(id: 'most_listened', name: 'Most Listened', createdAt: DateTime.now(), updatedAt: DateTime.now()),
      Playlist(id: 'early_listened', name: 'Early Listened', createdAt: DateTime.now(), updatedAt: DateTime.now()),
      Playlist(id: 'daily_mix', name: 'Daily Mix', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    ];
  }

  List<Playlist> get allPlaylists => [...systemPlaylists, ..._playlists];

  void refreshSystemPlaylists() {
    final mostPlayed = List<Music>.from(_musicList);
    mostPlayed.sort((a, b) => b.playCount.compareTo(a.playCount));
    _cachedMostListened = mostPlayed.take(30).where((m) => m.playCount > 0).toList();

    final earlyPlayed = List<Music>.from(_musicList);
    earlyPlayed.sort((a, b) => (b.lastPlayed ?? DateTime(0)).compareTo(a.lastPlayed ?? DateTime(0)));
    _cachedEarlyListened = earlyPlayed.take(30).where((m) => m.lastPlayed != null).toList();

    if (_musicList.isNotEmpty) {
      final List<Music> result = [..._cachedMostListened.take(10)];
      final genres = _musicList.map((m) => m.genre).toSet().toList();
      if (genres.isNotEmpty) {
        final randomGenre = genres[Random().nextInt(genres.length)];
        final genreList = _musicList.where((m) => m.genre == randomGenre).take(20).toList();
        result.addAll(genreList);
      }
      result.shuffle();
      _cachedDailyMix = result.toSet().toList();
    } else {
      _cachedDailyMix = [];
    }
    notifyListeners();
  }

  set currentIndex(int index) {
    if (index >= 0 && index < _musicList.length) {
      _currentIndex = index;
      notifyListeners();
    }
  }

  void _initAudioPlayer() {
    _audioPlayer.onPositionChanged.listen((position) {
      _position = position;
      notifyListeners();
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      _duration = duration;
      notifyListeners();
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (_isRepeatOne) {
        play();
      } else {
        next();
      }
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
  }

  List<Music> getMusicListForPlaylist(String playlistId) {
    if (playlistId == 'favorites') {
      return favoriteMusicList;
    } else if (playlistId == 'most_listened') {
      return _cachedMostListened;
    } else if (playlistId == 'early_listened') {
      return _cachedEarlyListened;
    } else if (playlistId == 'daily_mix') {
      return _cachedDailyMix;
    } else {
      final playlist = _playlists.firstWhere((p) => p.id == playlistId, orElse: () => Playlist(id: '', name: '', createdAt: DateTime.now(), updatedAt: DateTime.now()));
      return _musicList.where((m) => playlist.musicIds.contains(m.id)).toList();
    }
  }

  List<Cover> getCoverListForPlaylist(String playlistId) {
    final list = getMusicListForPlaylist(playlistId);
    return List.generate(list.length, (index) => Cover());
  }

  void removeMusicFromPlaylist(String playlistId, String musicId) {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index].musicIds.remove(musicId);
      _savePlaylists();
      notifyListeners();
    }
  }

  int get currentPlaylistIndex => _currentPlaylistIndex;
  set currentPlaylistIndex(int index) {
    _currentPlaylistIndex = index;
    notifyListeners();
  }

  void deletePlaylist(String playlistId) {
    _playlists.removeWhere((p) => p.id == playlistId);
    _savePlaylists();
    notifyListeners();
  }

  void playPlaylist(String playlistId) {
    final list = getMusicListForPlaylist(playlistId);
    if (list.isNotEmpty) {
      _currentPlaylistId = playlistId;
      final firstMusicId = list.first.id;
      final index = _musicList.indexWhere((m) => m.id == firstMusicId);
      if (index != -1) {
        _currentIndex = index;
        if (_isShuffle) _generateShuffleQueue();
        play();
      }
    }
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_isShuffle) {
      _generateShuffleQueue();
    } else {
      _queue.clear();
    }
    notifyListeners();
  }

  void _generateShuffleQueue() {
    _queue = List.generate(_musicList.length, (index) => index);
    _queue.remove(_currentIndex);
    _queue.shuffle();
    _queue.insert(0, _currentIndex);
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
    notifyListeners();
  }

  Future<void> play() async {
    if (_musicList.isEmpty || _currentIndex >= _musicList.length) return;

    try {
      final filePath = _musicList[_currentIndex].filePath;
      await _audioPlayer.stop();
      await _audioPlayer.play(DeviceFileSource(filePath));
      _isPlaying = true;
      
      _musicList[_currentIndex].playCount++;
      _musicList[_currentIndex].lastPlayed = DateTime.now();
      
      refreshSystemPlaylists();
      _saveStats();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Playback error: $e');
    }
  }

  Future<void> _saveStats() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_statsCacheFile');
      final data = _musicList.map((m) => m.toJson()).toList();
      await file.writeAsString(json.encode(data));
    } catch (e) {}
  }

  Future<void> _loadStats() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_statsCacheFile');
      if (await file.exists()) {
        final List data = json.decode(await file.readAsString());
        for (var item in data) {
          final idx = _musicList.indexWhere((m) => m.id == item['id']);
          if (idx != -1) {
            final m = _musicList[idx];
            _musicList[idx] = Music.fromBase(
              m, 
              item['playCount'] ?? 0, 
              item['lastPlayed'] != null ? DateTime.fromMillisecondsSinceEpoch(item['lastPlayed']) : null
            );
          }
        }
        refreshSystemPlaylists();
      }
    } catch (e) {}
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      if (_audioPlayer.state == PlayerState.paused) {
        await _audioPlayer.resume();
      } else {
        await play();
      }
    }
    notifyListeners();
  }

  Future<void> next() async {
    if (_musicList.isEmpty) return;

    if (_isShuffle) {
      int currentQueueIndex = _queue.indexOf(_currentIndex);
      if (currentQueueIndex < _queue.length - 1) {
        _currentIndex = _queue[currentQueueIndex + 1];
      } else if (_isRepeatAll) {
        _currentIndex = _queue[0];
      } else {
        await _audioPlayer.stop();
        _isPlaying = false;
        notifyListeners();
        return;
      }
    } else {
      if (_currentIndex < _musicList.length - 1) {
        _currentIndex++;
      } else if (_isRepeatAll) {
        _currentIndex = 0;
      } else {
        await _audioPlayer.stop();
        _isPlaying = false;
        notifyListeners();
        return;
      }
    }
    await play();
  }

  Future<void> previous() async {
    if (_musicList.isEmpty) return;

    if (_position.inSeconds > 3) {
      await _audioPlayer.seek(Duration.zero);
      return;
    }

    if (_isShuffle) {
      int currentQueueIndex = _queue.indexOf(_currentIndex);
      if (currentQueueIndex > 0) {
        _currentIndex = _queue[currentQueueIndex - 1];
      } else if (_isRepeatAll) {
        _currentIndex = _queue.last;
      }
    } else {
      if (_currentIndex > 0) {
        _currentIndex--;
      } else if (_isRepeatAll) {
        _currentIndex = _musicList.length - 1;
      }
    }
    await play();
  }

  Future<void> seekTo(Duration pos) async {
    await _audioPlayer.seek(pos);
    notifyListeners();
  }

  Future<void> loadSystemMusic() async {
    if (_isLoadingSystemMusic) return;
    
    _isLoadingSystemMusic = true;
    _musicList = [];
    notifyListeners();

    try {
      await MusicScannerService.startScanning(
        onProgress: (path) {
          _currentScanPath = path;
          notifyListeners();
        },
        onBatchUpdate: (newMusic) {
          _musicList.addAll(newMusic);
          _systemMusicCount = _musicList.length;
          refreshSystemPlaylists();
          notifyListeners();
        },
      );

      await _loadStats();
      if (_isShuffle) _generateShuffleQueue();
      await _loadFavoritesFromCache();
      
      refreshSystemPlaylists();
    } catch (e) {
      if (kDebugMode) print('Scan error: $e');
    }

    _isLoadingSystemMusic = false;
    _currentScanPath = '';
    notifyListeners();
  }

  Future<void> _loadFavoritesFromCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_favoritesCacheFile');
      if (await file.exists()) {
        final ids = json.decode(await file.readAsString()).cast<String>();
        for (var music in _musicList) {
          music.isFavorite = ids.contains(music.id);
        }
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<void> toggleFavorite(String musicId) async {
    final music = _musicList.firstWhere((m) => m.id == musicId);
    music.isFavorite = !music.isFavorite;
    notifyListeners();
    
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$_favoritesCacheFile');
    final ids = _musicList.where((m) => m.isFavorite).map((m) => m.id).toList();
    await file.writeAsString(json.encode(ids));
  }

  Future<void> _loadPlaylistsFromCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_playlistsCacheFile');
      if (await file.exists()) {
        final data = json.decode(await file.readAsString()) as List;
        _playlists = data.map((j) => Playlist.fromJson(j)).toList();
        notifyListeners();
      }
    } catch (e) {}
  }

  Future<void> createPlaylist(String name) async {
    final pl = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      musicIds: [],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _playlists.add(pl);
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> _savePlaylists() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$_playlistsCacheFile');
    await file.writeAsString(json.encode(_playlists.map((p) => p.toJson()).toList()));
  }

  void addMusicToPlaylist(String plId, String mId) {
    final pl = _playlists.firstWhere((p) => p.id == plId);
    if (!pl.musicIds.contains(mId)) {
      pl.musicIds.add(mId);
      _savePlaylists();
      notifyListeners();
    }
  }

  void deleteMusic(int index) {
    if (index < _musicList.length) {
      _musicList.removeAt(index);
      if (_currentIndex >= _musicList.length) _currentIndex = max(0, _musicList.length - 1);
      notifyListeners();
    }
  }

  Future<void> updateMusicMetadata(String musicId, String title, String artist, String album, String genre) async {
    final index = _musicList.indexWhere((m) => m.id == musicId);
    if (index != -1) {
      final oldMusic = _musicList[index];
      final newMusic = Music(
        id: oldMusic.id,
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        filePath: oldMusic.filePath,
        coverPath: oldMusic.coverPath,
        duration: oldMusic.duration,
        isFavorite: oldMusic.isFavorite,
        playCount: oldMusic.playCount,
        lastPlayed: oldMusic.lastPlayed,
      );
      
      _musicList[index] = newMusic;
      
      // Update cache
      await MusicScannerService.cacheMusic(newMusic, File(newMusic.filePath));
      
      notifyListeners();
    }
  }

  /// Clear all cached music data and re-scan
  Future<void> clearCache() async {
    await MusicScannerService.cleanupCache();
    _musicList = [];
    _systemMusicCount = 0;
    _cachedDailyMix = [];
    _cachedMostListened = [];
    _cachedEarlyListened = [];
    notifyListeners();
    await loadSystemMusic();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
