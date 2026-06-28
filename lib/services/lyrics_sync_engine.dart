import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/services/audio_analyzer.dart';

class LyricsSyncState {
  final int activeLineIndex;
  final int activeWordIndex;
  final LyricLine? activeLine;
  final LyricWord? activeWord;

  const LyricsSyncState({
    required this.activeLineIndex,
    required this.activeWordIndex,
    this.activeLine,
    this.activeWord,
  });

  factory LyricsSyncState.empty() => const LyricsSyncState(
        activeLineIndex: -1,
        activeWordIndex: -1,
      );
}

class LyricsSyncEngine {
  LyricsDocument? _document;
  Duration _driftOffset = Duration.zero;

  void setLyrics(LyricsDocument document) {
    _document = document;
    _driftOffset = Duration.zero;
  }

  LyricsDocument? get document => _document;

  void processAudioTransient(AudioTransientEvent event) {
    if (_document == null) return;
    
    // Simple drift correction logic:
    // If a beat/transient happens, we check if the active word's start time 
    // is very close to the current position. If there's a slight mismatch, 
    // we assume the lyric was meant to hit on this beat and adjust the drift offset.
    final state = getSyncState(event.position);
    if (state.activeWord != null) {
      final timeDiff = (state.activeWord!.startTime - event.position).inMilliseconds;
      if (timeDiff.abs() > 50 && timeDiff.abs() < 300) {
        // Correct drift slightly towards the beat
        _driftOffset += Duration(milliseconds: timeDiff ~/ 2);
      }
    }
  }

  LyricsSyncState getSyncState(Duration position) {
    if (_document == null || !_document!.hasTimedLines) {
      return LyricsSyncState.empty();
    }

    // Apply drift correction offset
    final effectivePosition = position + _driftOffset;
    
    final lines = _document!.lines;
    int activeLineIdx = -1;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.timestamp == null) continue;

      if (effectivePosition >= line.timestamp!) {
        if (line.endTime == null || effectivePosition <= line.endTime!) {
          activeLineIdx = i;
        } else if (i == lines.length - 1 || (lines[i + 1].timestamp != null && effectivePosition < lines[i + 1].timestamp!)) {
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

    if (activeLine.hasWords) {
      final words = activeLine.words!;
      for (int i = 0; i < words.length; i++) {
        final word = words[i];
        if (effectivePosition >= word.startTime && effectivePosition <= word.endTime) {
          activeWordIdx = i;
          break;
        } else if (effectivePosition > word.endTime && (i == words.length - 1 || effectivePosition < words[i + 1].startTime)) {
          activeWordIdx = i;
        }
      }
    }

    return LyricsSyncState(
      activeLineIndex: activeLineIdx,
      activeWordIndex: activeWordIdx,
      activeLine: activeLine,
      activeWord: activeWordIdx != -1 ? activeLine.words![activeWordIdx] : null,
    );
  }
}
