class LyricLine {
  final Duration? timestamp;
  final String text;

  const LyricLine({
    required this.timestamp,
    required this.text,
  });
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

  LyricsDocument shiftedBy(Duration offset) {
    if (offset == Duration.zero || !hasTimedLines) return this;
    final shiftedRaw = shiftRawTimestamps(rawText, offset);
    return LyricsDocument.parse(shiftedRaw, source: source);
  }

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
    final parsedLines = <LyricLine>[];
    final timeTagPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final metadataPattern = RegExp(r'^\[[a-zA-Z]+:.*\]$');

    for (final rawLine in rawText.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || metadataPattern.hasMatch(line)) continue;

      final matches = timeTagPattern.allMatches(line).toList();
      final text = line.replaceAll(timeTagPattern, '').trim();
      if (matches.isEmpty) {
        if (text.isNotEmpty) {
          parsedLines.add(LyricLine(timestamp: null, text: text));
        }
        continue;
      }

      for (final match in matches) {
        if (text.isEmpty) continue;
        parsedLines.add(
          LyricLine(
            timestamp: _parseTimestamp(match),
            text: text,
          ),
        );
      }
    }

    parsedLines.sort((a, b) {
      final left = a.timestamp;
      final right = b.timestamp;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });

    return LyricsDocument(
      rawText: rawText,
      lines: parsedLines,
      source: source,
    );
  }

  static String shiftRawTimestamps(String rawText, Duration offset) {
    final timeTagPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    return rawText.replaceAllMapped(timeTagPattern, (match) {
      final shifted = _parseTimestamp(match) + offset;
      final clamped = shifted.isNegative ? Duration.zero : shifted;
      return '[${_formatTimestamp(clamped)}]';
    });
  }

  static Duration _parseTimestamp(Match match) {
    final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
    final fraction = match.group(3) ?? '0';
    final milliseconds = fraction.length == 1
        ? int.parse(fraction) * 100
        : fraction.length == 2
            ? int.parse(fraction) * 10
            : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  static String _formatTimestamp(Duration timestamp) {
    final totalMilliseconds = timestamp.inMilliseconds;
    final minutes = totalMilliseconds ~/ Duration.millisecondsPerMinute;
    final seconds = (totalMilliseconds ~/ Duration.millisecondsPerSecond) % 60;
    final centiseconds = (totalMilliseconds % 1000) ~/ 10;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}.'
        '${centiseconds.toString().padLeft(2, '0')}';
  }
}
