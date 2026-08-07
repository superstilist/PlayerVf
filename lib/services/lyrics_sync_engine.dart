import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/services/audio_analyzer.dart';

class LyricsSyncState {
  final int activeLineIndex;
  final int activeWordIndex;
  final int activeSyllableIndex;
  final LyricLine? activeLine;
  final LyricWord? activeWord;
  final LyricSyllable? activeSyllable;
  final Duration currentPosition;

  const LyricsSyncState({
    required this.activeLineIndex,
    required this.activeWordIndex,
    this.activeSyllableIndex = -1,
    this.activeLine,
    this.activeWord,
    this.activeSyllable,
    this.currentPosition = Duration.zero,
  });

  factory LyricsSyncState.empty() => const LyricsSyncState(
        activeLineIndex: -1,
        activeWordIndex: -1,
      );

  bool get hasActiveSyllable =>
      activeSyllableIndex >= 0 && activeSyllable != null;

  bool get hasActiveWord => activeWordIndex >= 0 && activeWord != null;

  bool get hasActiveLine => activeLineIndex >= 0 && activeLine != null;
}

class LyricsSyncEngine {
  LyricsDocument? _document;
  Duration _globalDriftOffset = Duration.zero;
  final Map<int, Duration> _lineDriftOffsets = {};
  final Map<int, double> _lineConfidence = {};
  static const int _maxDriftMs = 2000;
  static const int _maxLineDriftMs = 500;
  int _lastActiveLineIdx = -1;

  /// Perceptual pre-advance: highlights lead audio by this amount so that
  /// human visual-processing latency (~80-120ms) is compensated and lyrics
  /// feel perfectly in sync. Set to Duration.zero to disable.
  Duration readAdvance = const Duration(milliseconds: 100);

  void setLyrics(LyricsDocument document) {
    _document = document;
    _globalDriftOffset = Duration.zero;
    _lineDriftOffsets.clear();
    _lineConfidence.clear();
  }

  LyricsDocument? get document => _document;

  /// Returns the effective drift for a specific line (global + line-specific).
  Duration _getEffectiveDrift(int lineIndex) {
    final lineDrift = _lineDriftOffsets[lineIndex] ?? Duration.zero;
    return _globalDriftOffset + lineDrift;
  }

  /// Applies a drift correction from a native word-timing callback.
  ///
  /// The word was scheduled at [lyricStartMs] but actually sung at
  /// [detectedStartMs]; the sync engine shifts timings so the word highlights
  /// exactly when it is heard. Corrections are smoothed adaptively — faster
  /// convergence for large drifts, gentler smoothing for small adjustments.
  void processWordTiming(int lyricStartMs, int detectedStartMs,
      {double confidence = 1.0}) {
    if (_document == null || !_document!.hasTimedLines) return;

    int? targetLineIndex;
    for (int i = 0; i < _document!.lines.length; i++) {
      final line = _document!.lines[i];
      if (line.timestamp == null) continue;
      final lineStart = line.timestamp!.inMilliseconds;
      final lineEnd =
          (line.endTime ?? line.timestamp! + const Duration(seconds: 5))
              .inMilliseconds;
      if (lyricStartMs >= lineStart && lyricStartMs < lineEnd) {
        targetLineIndex = i;
        break;
      }
    }

    if (targetLineIndex == null) {
      _applyGlobalDriftTarget(lyricStartMs - detectedStartMs, confidence);
      return;
    }

    final target = lyricStartMs - detectedStartMs;
    _applyLineDriftTarget(targetLineIndex, target, confidence);
  }

  /// Applies a weaker drift correction from a WebRTC VAD voice onset.
  ///
  /// Snaps the nearest upcoming lyric line to the detected vocal start. This
  /// keeps line-level sync on track even when PocketSphinx has not recognized
  /// any words yet.
  void processVoiceOnset(int detectedStartMs, {double confidence = 1.0}) {
    if (_document == null || !_document!.hasTimedLines) return;
    final current = _globalDriftOffset.inMilliseconds;
    for (final line in _document!.lines) {
      final ts = line.timestamp;
      if (ts == null) continue;
      final lineStart = ts.inMilliseconds;
      final effective = lineStart - current;
      if (effective >= detectedStartMs - 300 &&
          effective <= detectedStartMs + 1500) {
        _applyGlobalDriftTarget(lineStart - detectedStartMs, confidence);
        break;
      }
    }
  }

  void _applyGlobalDriftTarget(int targetMs, [double confidence = 1.0]) {
    final current = _globalDriftOffset.inMilliseconds;
    final diff = targetMs - current;
    if (diff.abs() < 3) {
      _globalDriftOffset = Duration(milliseconds: targetMs);
    } else {
      final confidenceFactor = confidence.clamp(0.2, 1.0);
      final magnitudeFactor = (diff.abs() / _maxDriftMs).clamp(0.15, 0.85);
      final t = magnitudeFactor * confidenceFactor;
      _globalDriftOffset = Duration(milliseconds: (current + diff * t).round());
    }
    final ms = _globalDriftOffset.inMilliseconds;
    if (ms > _maxDriftMs) {
      _globalDriftOffset = const Duration(milliseconds: _maxDriftMs);
    } else if (ms < -_maxDriftMs) {
      _globalDriftOffset = Duration(milliseconds: -_maxDriftMs);
    }
  }

  void _applyLineDriftTarget(int lineIndex, int targetMs,
      [double confidence = 1.0]) {
    final current = _lineDriftOffsets[lineIndex]?.inMilliseconds ?? 0;
    final diff = targetMs - current;
    if (diff.abs() < 3) {
      _lineDriftOffsets[lineIndex] = Duration(milliseconds: targetMs);
    } else {
      final confidenceFactor = confidence.clamp(0.2, 1.0);
      final magnitudeFactor = (diff.abs() / _maxLineDriftMs).clamp(0.1, 0.7);
      final t = magnitudeFactor * confidenceFactor;
      _lineDriftOffsets[lineIndex] =
          Duration(milliseconds: (current + diff * t).round());
    }
    final ms = _lineDriftOffsets[lineIndex]!.inMilliseconds;
    if (ms > _maxLineDriftMs) {
      _lineDriftOffsets[lineIndex] =
          const Duration(milliseconds: _maxLineDriftMs);
    } else if (ms < -_maxLineDriftMs) {
      _lineDriftOffsets[lineIndex] = Duration(milliseconds: -_maxLineDriftMs);
    }
    _lineConfidence[lineIndex] =
        (_lineConfidence[lineIndex] ?? 0.0) * 0.7 + confidence * 0.3;
  }

  void processAudioTransient(AudioTransientEvent event) {
    if (_document == null) return;

    final state = getSyncState(event.position);
    if (state.activeWord != null && state.activeLine != null) {
      final timeDiff =
          (state.activeWord!.startTime - event.position).inMilliseconds;
      if (timeDiff.abs() > 50 && timeDiff.abs() < 300) {
        final confidence = _lineConfidence[state.activeLineIndex] ?? 0.5;
        _applyLineDriftTarget(state.activeLineIndex, timeDiff ~/ 2, confidence);
      }
    }
  }

  /// Returns the progress of the active word as a 0.0-1.0 value, or null if
  /// there is no active word.
  double? getWordProgress(Duration position,
      {required int lineIndex, required int wordIndex}) {
    if (_document == null) return null;
    final lines = _document!.lines;
    if (lineIndex < 0 || lineIndex >= lines.length) return null;
    final line = lines[lineIndex];
    if (!line.hasWords || wordIndex < 0 || wordIndex >= line.words!.length)
      return null;
    final word = line.words![wordIndex];
    final effectiveDrift = _getEffectiveDrift(lineIndex).inMilliseconds;
    final effectivePosition = position.inMilliseconds + effectiveDrift;
    final wordStart = word.startTime.inMilliseconds;
    final wordEnd = word.endTime.inMilliseconds;
    final wordDuration = wordEnd - wordStart;
    if (wordDuration <= 0) return null;
    final elapsed = effectivePosition - wordStart;
    return (elapsed / wordDuration).clamp(0.0, 1.0);
  }

  /// Returns the progress of the active syllable as a 0.0-1.0 value, or null
  /// if there is no active syllable.
  double? getSyllableProgress(
    Duration position, {
    required int lineIndex,
    required int wordIndex,
    required int syllableIndex,
  }) {
    if (_document == null) return null;
    final lines = _document!.lines;
    if (lineIndex < 0 || lineIndex >= lines.length) return null;
    final line = lines[lineIndex];
    if (!line.hasWords || wordIndex < 0 || wordIndex >= line.words!.length) {
      return null;
    }
    final word = line.words![wordIndex];
    if (!word.hasSyllables ||
        syllableIndex < 0 ||
        syllableIndex >= word.syllables!.length) {
      return null;
    }
    final syllable = word.syllables![syllableIndex];
    final effectiveDrift = _getEffectiveDrift(lineIndex).inMilliseconds;
    final effectivePosition = position.inMilliseconds + effectiveDrift;
    final sylStart = syllable.startTime.inMilliseconds;
    final sylEnd = syllable.endTime.inMilliseconds;
    final sylDuration = sylEnd - sylStart;
    if (sylDuration <= 0) return null;
    final elapsed = effectivePosition - sylStart;
    return (elapsed / sylDuration).clamp(0.0, 1.0);
  }

  double getLineConfidence(int lineIndex) {
    return _lineConfidence[lineIndex] ?? 0.0;
  }

  LyricsSyncState getSyncState(Duration position) {
    if (_document == null || !_document!.hasTimedLines) {
      return LyricsSyncState.empty();
    }

    // Apply perceptual read-advance for lookup only; real position is
    // preserved in the returned state so seeking and display stay correct.
    final lookupPosition = position + readAdvance;

    // Apply drift correction offset (global + line-specific)
    final lines = _document!.lines;
    int activeLineIdx = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.timestamp == null) continue;

      final effectiveDrift = _getEffectiveDrift(i).inMilliseconds;
      final effectivePosition = lookupPosition.inMilliseconds + effectiveDrift;
      final lineStart = line.timestamp!.inMilliseconds;

      if (effectivePosition >= lineStart) {
        final lineEnd =
            (line.endTime ?? line.timestamp! + const Duration(seconds: 5))
                .inMilliseconds;
        if (effectivePosition <= lineEnd) {
          activeLineIdx = i;
        } else if (i == lines.length - 1 ||
            (lines[i + 1].timestamp != null &&
                effectivePosition < lines[i + 1].timestamp!.inMilliseconds)) {
          activeLineIdx = i;
        }
      } else {
        break;
      }
    }

    if (activeLineIdx == -1) {
      return LyricsSyncState.empty();
    }

    final activeLine = lines[activeLineIdx];
    int activeWordIdx = -1;
    int activeSyllableIdx = -1;

    if (activeLine.hasWords) {
      final words = activeLine.words!;
      final effectiveDrift = _getEffectiveDrift(activeLineIdx).inMilliseconds;
      final effectivePosition = lookupPosition.inMilliseconds + effectiveDrift;

      for (int i = 0; i < words.length; i++) {
        final word = words[i];
        if (effectivePosition >= word.startTime.inMilliseconds) {
          if (effectivePosition > word.endTime.inMilliseconds) {
            activeWordIdx = i + 1;
          } else {
            activeWordIdx = i;

            if (word.hasSyllables) {
              for (int j = 0; j < word.syllables!.length; j++) {
                final syllable = word.syllables![j];
                if (effectivePosition >= syllable.startTime.inMilliseconds) {
                  if (effectivePosition > syllable.endTime.inMilliseconds) {
                    activeSyllableIdx = j + 1;
                  } else {
                    activeSyllableIdx = j;
                    break;
                  }
                } else {
                  break;
                }
              }
            }
            break;
          }
        } else {
          break;
        }
      }
    }

    return LyricsSyncState(
      activeLineIndex: activeLineIdx,
      activeWordIndex: activeWordIdx,
      activeSyllableIndex: activeSyllableIdx,
      activeLine: activeLine,
      activeWord: activeWordIdx != -1 ? activeLine.words![activeWordIdx] : null,
      activeSyllable: (activeWordIdx != -1 &&
              activeSyllableIdx >= 0 &&
              activeLine.words![activeWordIdx].hasSyllables)
          ? activeLine.words![activeWordIdx].syllables![activeSyllableIdx]
          : null,
      currentPosition: position, // real position (not advanced)
    );
  }
}
