import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/services/lyrics_sync_engine.dart';
import 'package:player_vf/services/charter_sync_engine.dart';
import 'package:player_vf/services/audio_analyzer.dart';
import 'package:player_vf/services/lyrics_aligner_service.dart';
import 'package:player_vf/services/cpp_core_bridge.dart';

class LyricsController extends ChangeNotifier {
  final Stream<Duration> positionStream;
  final AudioAnalyzer? audioAnalyzer;
  final LyricsSyncEngine _syncEngine = LyricsSyncEngine();
  final CharterSyncEngine _charterEngine = CharterSyncEngine();
  final void Function(Duration)? onSeek;

  LyricsDocument? _currentLyrics;
  LyricsSyncState _syncState = LyricsSyncState.empty();
  EnhancedSyncState? _enhancedSyncState;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<AudioTransientEvent>? _transientSubscription;
  StreamSubscription<LyricsAlignerEvent>? _wordTimingSubscription;
  StreamSubscription<LyricsVoiceOnsetEvent>? _onsetSubscription;
  StreamSubscription<VocalFrameEvent>? _vocalFrameSubscription;
  StreamSubscription<EnhancedSyncState>? _enhancedStateSubscription;
  Duration _lastPosition = Duration.zero;
  int _pendingLineIndex = -1;
  bool _alignerConfigured = false;

  /// Notifier updated whenever syncState changes — subscribe to this in
  /// per-line widgets so only changed lines rebuild (not the whole list).
  final ValueNotifier<LyricsSyncState> syncStateNotifier =
      ValueNotifier(LyricsSyncState.empty());

  /// True for one frame after a large seek so the view can
  /// decide to jump instead of spring-scroll.
  bool seekJustHappened = false;

  LyricsController({
    required this.positionStream,
    this.audioAnalyzer,
    this.onSeek,
  }) {
    _initListeners();
  }

  // Backward-compat constructor for code that still has AudioPlayer
  factory LyricsController.fromAudioPlayer({
    required AudioPlayer audioPlayer,
    AudioAnalyzer? audioAnalyzer,
    void Function(Duration)? onSeek,
  }) {
    return LyricsController(
      positionStream: audioPlayer.positionStream,
      audioAnalyzer: audioAnalyzer,
      onSeek: onSeek,
    );
  }

  LyricsDocument? get currentLyrics => _currentLyrics;
  LyricsSyncState get syncState => _syncState;
  EnhancedSyncState? get enhancedSyncState => _enhancedSyncState;
  LyricsSyncEngine get syncEngine => _syncEngine;
  CharterSyncEngine get charterEngine => _charterEngine;

  void _initListeners() {
    _positionSubscription = positionStream.listen((position) {
      _lastPosition = position;
      _updateFromPosition(position);
    });

    _transientSubscription = audioAnalyzer?.transientStream.listen((event) {
      if (_currentLyrics != null) {
        _syncEngine.processAudioTransient(event);
      }
    });

    _wordTimingSubscription =
        LyricsAlignerService.instance.wordTimingEvents.listen((event) {
      if (_currentLyrics == null) return;
      _syncEngine.processWordTiming(event.lyricStartMs, event.detectedStartMs, confidence: event.confidence);
      _charterEngine.processWordTiming(event.lyricStartMs, event.detectedStartMs, confidence: event.confidence);
      _updateFromPosition(_lastPosition);
    });

    _onsetSubscription = LyricsAlignerService.instance.voiceOnsetEvents.listen(
        (event) {
      if (_currentLyrics == null) return;
      _syncEngine.processVoiceOnset(event.onsetMs);
      _charterEngine.processVoiceOnset(event.onsetMs, confidence: 0.8);
      _updateFromPosition(_lastPosition);
    });

    // Wire up vocal frame callbacks from C++ bridge
    _vocalFrameSubscription = LyricsAlignerService.instance.vocalFrameEvents.listen((event) {
      if (_currentLyrics == null) return;
      _charterEngine.processVocalSegment(
        event.timestampMs,
        event.timestampMs + 50,
        event.isVocal,
        event.vocalProbability,
      );
    });

    // Enable vocal detection in C++ engine. The vocal-frame listener is
    // registered once by LyricsAlignerService — re-attaching here would
    // clobber that slot on every controller instance.
    CppCoreBridge.setVocalDetectionEnabled(true);

    // Subscribe to enhanced sync state from CharterSyncEngine
    _enhancedStateSubscription = _charterEngine.stateStream.listen((state) {
      _enhancedSyncState = state;
      notifyListeners();
    });
  }

  void _updateFromPosition(Duration position) {
    if (_currentLyrics == null) return;

    // Detect large seeks so the view can decide to jump rather than spring.
    final seekJump =
        (_lastPosition - position).abs() > const Duration(milliseconds: 500);
    _lastPosition = position;
    seekJustHappened = seekJump;

    final newState = _syncEngine.getSyncState(position);

    // Check if active line changed
    if (newState.activeLineIndex != _syncState.activeLineIndex) {
      _onActiveLineChanged(newState.activeLineIndex, newState.activeLine);
    }

    // Notify on index transitions AND on seeks: even when a seek lands inside
    // the same word/syllable, the active-word sweep must re-sync so its fill
    // matches the real word timing again.
    if (newState.activeLineIndex != _syncState.activeLineIndex ||
        newState.activeWordIndex != _syncState.activeWordIndex ||
        newState.activeSyllableIndex != _syncState.activeSyllableIndex ||
        seekJump) {
      _syncState = newState;
      syncStateNotifier.value = newState;
      notifyListeners();
    }
  }

  void _onActiveLineChanged(int newLineIndex, LyricLine? newLine) {
    if (newLineIndex == -1 || newLine == null) {
      _pendingLineIndex = -1;
      return;
    }

    if (_pendingLineIndex == newLineIndex) return;
    _pendingLineIndex = newLineIndex;

    // Configure once per loaded document; the aligner tracks the whole
    // schedule internally, so per-line reconfiguration is unnecessary and
    // re-enables VAD/PocketSphinx every time the active line advances.
    if (_currentLyrics != null && !_alignerConfigured) {
      _alignerConfigured = true;
      LyricsAlignerService.instance.configure(_currentLyrics!);
    }
  }

  void loadLyrics(LyricsDocument document) {
    _currentLyrics = document;
    _syncEngine.setLyrics(document);
    _charterEngine.loadLyrics(document);
    _syncState = LyricsSyncState.empty();
    syncStateNotifier.value = LyricsSyncState.empty();
    _pendingLineIndex = -1;
    _alignerConfigured = false;

    LyricsAlignerService.instance.configure(document);
    _alignerConfigured = true;

    notifyListeners();
  }

  void clearLyrics() {
    _currentLyrics = null;
    _syncEngine.setLyrics(const LyricsDocument(rawText: '', lines: [], source: ''));
    _charterEngine.clear();
    _syncState = LyricsSyncState.empty();
    syncStateNotifier.value = LyricsSyncState.empty();
    _pendingLineIndex = -1;
    _alignerConfigured = false;

    LyricsAlignerService.instance.clear();

    notifyListeners();
  }

  void seekToLine(int lineIndex) {
    if (_currentLyrics == null || lineIndex < 0 || lineIndex >= _currentLyrics!.lines.length) return;
    final line = _currentLyrics!.lines[lineIndex];
    if (line.timestamp != null) {
      onSeek?.call(line.timestamp!);
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _transientSubscription?.cancel();
    _wordTimingSubscription?.cancel();
    _onsetSubscription?.cancel();
    _vocalFrameSubscription?.cancel();
    _enhancedStateSubscription?.cancel();
    _charterEngine.dispose();
    syncStateNotifier.dispose();
    super.dispose();
  }
}