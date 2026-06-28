import 'dart:math' as math;
import 'package:player_vf/models/lyrics_model.dart';

class KaraokeLineSync {
  final int activeIndex;
  final int nextIndex;
  final int activeWordIndex;
  final double fillProgress;
  final double activeWordProgress;
  final double transitionProgress;
  final Duration lineStart;
  final Duration lineEnd;
  final Duration fillEnd;
  final Duration fillDuration;
  final Duration transitionDuration;
  final bool isShortInterval;
  final bool isLastLine;

  const KaraokeLineSync({
    required this.activeIndex,
    required this.nextIndex,
    required this.activeWordIndex,
    required this.fillProgress,
    required this.activeWordProgress,
    required this.transitionProgress,
    required this.lineStart,
    required this.lineEnd,
    required this.fillEnd,
    required this.fillDuration,
    required this.transitionDuration,
    required this.isShortInterval,
    required this.isLastLine,
  });

  static const empty = KaraokeLineSync(
    activeIndex: -1,
    nextIndex: -1,
    activeWordIndex: -1,
    fillProgress: 0.0,
    activeWordProgress: 0.0,
    transitionProgress: 0.0,
    lineStart: Duration.zero,
    lineEnd: Duration.zero,
    fillEnd: Duration.zero,
    fillDuration: Duration.zero,
    transitionDuration: Duration.zero,
    isShortInterval: true,
    isLastLine: true,
  );
}

class KaraokeSyncCalculator {
  final int transitionGapMs;

  const KaraokeSyncCalculator({this.transitionGapMs = 700});

  KaraokeLineSync compute({
    required LyricsDocument lyrics,
    required int activeIndex,
    required Duration position,
  }) {
    if (activeIndex < 0 || activeIndex >= lyrics.lines.length) {
      return KaraokeLineSync.empty;
    }

    final line = lyrics.lines[activeIndex];
    final lineStart = line.timestamp ?? Duration.zero;

    final nextIndex = _nextTimedIndex(lyrics, activeIndex);
    final hasNext = nextIndex != -1;
    final nextStart = hasNext ? lyrics.lines[nextIndex].timestamp : null;

    final bool isLastLine;
    final Duration lineEnd;
    final Duration fillEnd;
    final Duration fillDuration;
    final Duration transitionDuration;
    final bool isShortInterval;

    if (!hasNext || nextStart == null || nextStart <= lineStart) {
      isLastLine = true;
      final explicitEnd = line.endTime;
      lineEnd = explicitEnd != null && explicitEnd > lineStart
          ? explicitEnd
          : lineStart + _fallbackLineDuration(line);
      fillEnd = lineEnd;
      fillDuration = lineEnd - lineStart;
      transitionDuration = Duration.zero;
      isShortInterval = false;
    } else {
      isLastLine = false;
      lineEnd = nextStart;
      final delayMs = (lineEnd - lineStart).inMilliseconds;
      final handoverMs = math.min(transitionGapMs, math.max(0, delayMs ~/ 2));
      final fillMs = math.max(1, delayMs - handoverMs);
      fillDuration = Duration(milliseconds: fillMs);
      transitionDuration = Duration(milliseconds: handoverMs);
      fillEnd = lineStart + fillDuration;
      isShortInterval = delayMs <= transitionGapMs;
    }

    final fillProgress = _computeFillProgress(
      position: position,
      lineStart: lineStart,
      fillDuration: fillDuration,
    );

    final transitionProgress = _computeTransitionProgress(
      position: position,
      lineStart: lineStart,
      fillDuration: fillDuration,
      transitionDuration: transitionDuration,
    );

    final activeWordIndex =
        line.hasWords ? _activeWordIndex(line, position) : -1;
    final activeWordProgress = activeWordIndex == -1
        ? 0.0
        : _wordProgress(line.words![activeWordIndex], position);

    return KaraokeLineSync(
      activeIndex: activeIndex,
      nextIndex: hasNext ? nextIndex : -1,
      activeWordIndex: activeWordIndex,
      fillProgress: fillProgress,
      activeWordProgress: activeWordProgress,
      transitionProgress: transitionProgress,
      lineStart: lineStart,
      lineEnd: lineEnd,
      fillEnd: fillEnd,
      fillDuration: fillDuration,
      transitionDuration: transitionDuration,
      isShortInterval: isShortInterval,
      isLastLine: isLastLine,
    );
  }

  static int _nextTimedIndex(LyricsDocument lyrics, int activeIndex) {
    for (var i = activeIndex + 1; i < lyrics.lines.length; i++) {
      final timestamp = lyrics.lines[i].timestamp;
      if (timestamp != null) return i;
    }
    return -1;
  }

  static Duration _fallbackLineDuration(LyricLine line) {
    if (line.hasWords) {
      final words = line.words!;
      final start = line.timestamp ?? Duration.zero;
      final end = words.last.endTime;
      if (end > start) return end - start;
    }
    final textWeight = math.max(16, line.text.trim().length);
    return Duration(milliseconds: (textWeight * 95).clamp(2600, 5200).round());
  }

  double _computeFillProgress({
    required Duration position,
    required Duration lineStart,
    required Duration fillDuration,
  }) {
    if (position < lineStart) return 0.0;

    final fillMs = fillDuration.inMilliseconds;
    if (fillMs <= 0) {
      return 1.0;
    }

    final rawTime =
        ((position - lineStart).inMilliseconds / fillMs).clamp(0.0, 1.0);
    return rawTime >= 0.985 ? 1.0 : rawTime.toDouble();
  }

  double _computeTransitionProgress({
    required Duration position,
    required Duration lineStart,
    required Duration fillDuration,
    required Duration transitionDuration,
  }) {
    final fillMs = fillDuration.inMilliseconds;
    final rawFill =
        fillMs <= 0 ? 1.0 : (position - lineStart).inMilliseconds / fillMs;
    if (rawFill < 1.0) return 0.0;

    final transitionStart = lineStart + fillDuration;
    final transitionMs = math.max(1, transitionDuration.inMilliseconds);
    final raw = (position - transitionStart).inMilliseconds / transitionMs;
    return _easeInOut(raw.clamp(0.0, 1.0));
  }

  static double _easeInOut(double t) {
    return t < 0.5
        ? 4.0 * t * t * t
        : 1.0 - math.pow(-2.0 * t + 2.0, 3.0) / 2.0;
  }

  static int _activeWordIndex(LyricLine line, Duration position) {
    final words = line.words!;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      if (position >= word.startTime && position <= word.endTime) {
        return i;
      }
      if (position > word.endTime &&
          (i == words.length - 1 || position < words[i + 1].startTime)) {
        return i;
      }
    }
    return -1;
  }

  static double _wordProgress(LyricWord word, Duration position) {
    final durationMs = word.duration.inMilliseconds;
    if (durationMs <= 0) return position >= word.endTime ? 1.0 : 0.0;
    return ((position - word.startTime).inMilliseconds / durationMs)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}
