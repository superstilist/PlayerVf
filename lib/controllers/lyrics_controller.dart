import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/services/lyrics_sync_engine.dart';
import 'package:player_vf/services/audio_analyzer.dart';

class LyricsController extends ChangeNotifier {
  final AudioPlayer audioPlayer;
  final LyricsSyncEngine _syncEngine = LyricsSyncEngine();
  late final AudioAnalyzer _audioAnalyzer;

  LyricsDocument? _currentLyrics;
  LyricsSyncState _syncState = LyricsSyncState.empty();

  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<AudioTransientEvent>? _transientSubscription;

  LyricsController({required this.audioPlayer}) {
    _audioAnalyzer = AudioAnalyzer(audioPlayer: audioPlayer);
    _initListeners();
  }

  LyricsDocument? get currentLyrics => _currentLyrics;
  LyricsSyncState get syncState => _syncState;

  void _initListeners() {
    _positionSubscription = audioPlayer.positionStream.listen((position) {
      if (_currentLyrics == null) return;

      final newState = _syncEngine.getSyncState(position);
      if (newState.activeLineIndex != _syncState.activeLineIndex ||
          newState.activeWordIndex != _syncState.activeWordIndex) {
        _syncState = newState;
        notifyListeners();
      }
    });

    _transientSubscription = _audioAnalyzer.transientStream.listen((event) {
      if (_currentLyrics != null) {
        _syncEngine.processAudioTransient(event);
      }
    });
  }

  void loadLyrics(LyricsDocument document) {
    _currentLyrics = document;
    _syncEngine.setLyrics(document);
    _syncState = LyricsSyncState.empty();
    notifyListeners();
  }

  void clearLyrics() {
    _currentLyrics = null;
    _syncEngine.setLyrics(LyricsDocument(rawText: '', lines: [], source: ''));
    _syncState = LyricsSyncState.empty();
    notifyListeners();
  }

  void seekToLine(int lineIndex) {
    if (_currentLyrics == null || lineIndex < 0 || lineIndex >= _currentLyrics!.lines.length) return;
    
    final line = _currentLyrics!.lines[lineIndex];
    if (line.timestamp != null) {
      audioPlayer.seek(line.timestamp!);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _transientSubscription?.cancel();
    _audioAnalyzer.dispose();
    super.dispose();
  }
}
