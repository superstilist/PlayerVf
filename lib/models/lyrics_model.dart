import 'package:player_vf/utils/lyrics_parser.dart';

class LyricWord {
  final String text;
  final Duration startTime;
  final Duration endTime;
  final bool hasComma;
  final bool hasPeriod;

  const LyricWord({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.hasComma = false,
    this.hasPeriod = false,
  });

  Duration get duration => endTime - startTime;

  LyricWord copyWith({
    String? text,
    Duration? startTime,
    Duration? endTime,
    bool? hasComma,
    bool? hasPeriod,
  }) {
    return LyricWord(
      text: text ?? this.text,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      hasComma: hasComma ?? this.hasComma,
      hasPeriod: hasPeriod ?? this.hasPeriod,
    );
  }
}

class LyricLine {
  final Duration? timestamp;
  final Duration? endTime;
  final String text;
  final List<LyricWord>? words;

  const LyricLine({
    required this.timestamp,
    this.endTime,
    required this.text,
    this.words,
  });

  bool get hasWords => words != null && words!.isNotEmpty;

  LyricLine copyWith({
    Duration? timestamp,
    Duration? endTime,
    String? text,
    List<LyricWord>? words,
  }) {
    return LyricLine(
      timestamp: timestamp ?? this.timestamp,
      endTime: endTime ?? this.endTime,
      text: text ?? this.text,
      words: words ?? this.words,
    );
  }
}

class LyricsDocument {
  final String rawText;
  final List<LyricLine> lines;
  final String source;

  const LyricsDocument({
    required this.rawText,
    required this.lines,
    required this.source,
  });

  bool get hasTimedLines => lines.any((line) => line.timestamp != null);

  String get plainText => lines
      .map((line) => line.text.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');

  int activeIndexAt(Duration position) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      final timestamp = lines[i].timestamp;
      if (timestamp == null) continue;
      if (timestamp <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  static LyricsDocument parse(String rawText, {required String source}) {
    return LyricsParser.parse(rawText, source: source);
  }

  LyricsDocument shiftedBy(Duration offset) {
    if (offset == Duration.zero || !hasTimedLines) return this;
    final shiftedRaw = shiftRawTimestamps(rawText, offset);
    return LyricsDocument.parse(shiftedRaw, source: source);
  }

  static String shiftRawTimestamps(String rawText, Duration offset) {
    final timeTagPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    return rawText.replaceAllMapped(timeTagPattern, (match) {
      final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
      final fraction = match.group(3) ?? '0';
      final milliseconds = fraction.length == 1
          ? int.parse(fraction) * 100
          : fraction.length == 2
              ? int.parse(fraction) * 10
              : int.parse(fraction.padRight(3, '0').substring(0, 3));
      final timestamp = Duration(
        minutes: minutes,
        seconds: seconds,
        milliseconds: milliseconds,
      );
      final shifted = timestamp + offset;
      final clamped = shifted.isNegative ? Duration.zero : shifted;
      
      final totalMilliseconds = clamped.inMilliseconds;
      final m = totalMilliseconds ~/ Duration.millisecondsPerMinute;
      final s = (totalMilliseconds ~/ Duration.millisecondsPerSecond) % 60;
      final cs = (totalMilliseconds % 1000) ~/ 10;
      return '[${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}.'
          '${cs.toString().padLeft(2, '0')}]';
    });
  }
}
