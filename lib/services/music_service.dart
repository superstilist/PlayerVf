import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

import '../models/music_model.dart';
import '../models/cover_model.dart';
import '../services/cover_extractor.dart';
import '../services/id3_parser.dart';

class MusicService extends ChangeNotifier {
  List<Music> _musicList = [];
  List<Cover?> _coverList = [];
  int _currentIndex = 0;
  final CoverExtractor _coverExtractor = CoverExtractor();
  final ID3Parser _id3Parser = ID3Parser();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Duration _duration = Duration(minutes: 3, seconds: 30);
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  Future<void>? _loadMusicFuture;

  List<Music> get musicList => _musicList;
  List<Cover?> get coverList => _coverList;
  int get currentIndex => _currentIndex;
  set currentIndex(int index) {
    if (index >= 0 && index < _musicList.length) {
      _currentIndex = index;
      notifyListeners();
      // Load and play the new track
      _loadCurrentTrack();
    }
  }
  Music? get currentMusic => _musicList.isNotEmpty ? _musicList[_currentIndex] : null;
  Cover? get currentCover => _coverList.isNotEmpty ? _coverList[_currentIndex] : null;
  bool get isPlaying => _isPlaying;
  Duration get duration => _duration;
  Duration get position => _position;

  MusicService() {
    // Listen to audio player state changes
    _audioPlayer.onPlayerStateChanged.listen((playerState) {
      _isPlaying = playerState == PlayerState.playing;
      notifyListeners();
    });
    
    // Listen to position changes
    _audioPlayer.onPositionChanged.listen((position) {
      _position = position;
      notifyListeners();
    });
    
    // Listen to duration changes
    _audioPlayer.onDurationChanged.listen((duration) {
      _duration = duration;
      notifyListeners();
    });

    // Listen for player completion
    _audioPlayer.onPlayerComplete.listen((_) {
      next();
    });
  }

  Future<void> _loadCurrentTrack() async {
    if (_musicList.isEmpty || _currentIndex >= _musicList.length) return;
    
    final music = _musicList[_currentIndex];
    try {
      // For asset files in audioplayers, use AssetSource
      // assets/music/song.mp3 -> music/song.mp3
      final assetPath = music.filePath.replaceFirst('assets/', '');
      await _audioPlayer.play(AssetSource(assetPath));
    } catch (e) {
      print('Error loading track: $e');
    }
  }

  Future<void> loadMusic() async {
    // Return cached future if already loading/loaded
    if (_loadMusicFuture != null) {
      return _loadMusicFuture!;
    }
    
    _loadMusicFuture = _loadMusicInternal();
    return _loadMusicFuture!;
  }

  Future<void> _loadMusicInternal() async {
    try {
      final manifestContent = await rootBundle.loadString('AssetManifest.json');
      final manifestMap = json.decode(manifestContent) as Map<String, dynamic>;

      final musicAssets = manifestMap.keys
          .where((String key) => key.startsWith('assets/music/'))
          .toList();

      final musicAndCovers = await Future.wait(musicAssets.map((musicPath) async {
        final fileName = path.basenameWithoutExtension(musicPath);
        
        // Parse ID3 tags
        final tags = await _id3Parser.parseTagsFromAsset(musicPath);
        
        // Extract cover art
        Cover? cover;
        final coverData = _id3Parser.extractCover(tags);
        if (coverData != null) {
          cover = Cover(
            id: 'cover_$fileName',
            filePath: musicPath,
            imageData: coverData,
          );
        }
        
        // Create Music object from tags
        final music = _id3Parser.createMusicFromTags(musicPath, tags);
        
        // Set approximate duration for each track
        const approximateDuration = Duration(minutes: 3, seconds: 30);
        music.duration = approximateDuration;
        
        return {
          'music': music,
          'cover': cover
        };
      }));

      _musicList = musicAndCovers.map((item) => item['music'] as Music).toList();
      _coverList = musicAndCovers.map((item) => item['cover'] as Cover?).toList();
      notifyListeners();
    } catch (e) {
      print('Error loading music: $e');
      rethrow;
    }
  }

  Future<void> play() async {
    if (_musicList.isEmpty) {
      await loadMusic();
    }
    if (_musicList.isNotEmpty) {
      try {
        // If not already playing, load and play
        if (_audioPlayer.state != PlayerState.playing) {
          await _loadCurrentTrack();
        }
        await _audioPlayer.resume();
        _isPlaying = true;
        notifyListeners();
      } catch (e) {
        print('Error playing music: $e');
      }
    }
  }

  void pause() {
    _audioPlayer.pause();
    _isPlaying = false;
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      pause();
    } else {
      await play();
    }
  }

  Future<void> next() async {
    if (_musicList.isEmpty) {
      await loadMusic();
    }
    if (_musicList.isNotEmpty) {
      _currentIndex = (_currentIndex + 1) % _musicList.length;
      notifyListeners();
      await _loadCurrentTrack();
      await _audioPlayer.resume();
    }
  }

  Future<void> previous() async {
    if (_musicList.isEmpty) {
      await loadMusic();
    }
    if (_musicList.isNotEmpty) {
      _currentIndex = (_currentIndex - 1 + _musicList.length) % _musicList.length;
      notifyListeners();
      await _loadCurrentTrack();
      await _audioPlayer.resume();
    }
  }

  Future<void> seekTo(Duration position) async {
    await _audioPlayer.seek(position);
    _position = position;
    notifyListeners();
  }

  Future<void> setVolume(double volume) async {
    await _audioPlayer.setVolume(volume);
    notifyListeners();
  }

  Future<void> setSpeed(double speed) async {
    await _audioPlayer.setPlaybackRate(speed);
    notifyListeners();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}
