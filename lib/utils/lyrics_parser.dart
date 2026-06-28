import 'package:player_vf/models/lyrics_model.dart';

class LyricsParser {
  static final RegExp _lrcTimePattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _metadataPattern = RegExp(r'^\[[a-zA-Z]+:.*\]$');

  static LyricsDocument parse(String rawText, {required String source}) {
    if (_lrcTimePattern.hasMatch(rawText)) {
      return _parseLrc(rawText, source: source);
    } 
    return _parsePlainText(rawText, source: source);
  }

  static LyricsDocument _parseLrc(String rawText, {required String source}) {
    final parsedLines = <LyricLine>[];

    final rawLines = rawText.replaceAll('\r\n', '\n').split('\n');
    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i].trim();
      if (line.isEmpty || _metadataPattern.hasMatch(line)) continue;

      final matches = _lrcTimePattern.allMatches(line).toList();
      final text = line.replaceAll(_lrcTimePattern, '').trim();
      if (matches.isEmpty) {
        if (text.isNotEmpty) {
          parsedLines.add(LyricLine(timestamp: null, text: text));
        }
        continue;
      }

      for (final match in matches) {
        if (text.isEmpty) continue;
        final timestamp = _parseTimestamp(match);
        parsedLines.add(LyricLine(timestamp: timestamp, text: text));
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

    final linesWithTiming = _generateLineEndingsAndWords(parsedLines);

    return LyricsDocument(
      rawText: rawText,
      lines: linesWithTiming,
      source: source,
    );
  }

  static LyricsDocument _parsePlainText(String rawText, {required String source}) {
    final parsedLines = rawText
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((text) => LyricLine(timestamp: null, text: text.trim()))
        .toList();

    return LyricsDocument(rawText: rawText, lines: parsedLines, source: source);
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
    return Duration(minutes: minutes, seconds: seconds, milliseconds: milliseconds);
  }

  static List<LyricLine> _generateLineEndingsAndWords(List<LyricLine> lines) {
    final result = <LyricLine>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.timestamp == null) {
        result.add(line);
        continue;
      }

      Duration? endTime;
      if (i < lines.length - 1 && lines[i + 1].timestamp != null) {
        endTime = lines[i + 1].timestamp!;
        // Ensure some gap before the next line if they are far apart
        if ((endTime - line.timestamp!).inMilliseconds > 7000) {
          endTime = line.timestamp! + const Duration(seconds: 5); // Give singing room to fade
        }
      } else {
        endTime = line.timestamp! + const Duration(seconds: 5);
      }

      final lineDuration = endTime - line.timestamp!;
      final words = _splitIntoWordsSemantic(line.text, line.timestamp!, lineDuration);

      result.add(line.copyWith(endTime: endTime, words: words));
    }
    return result;
  }

  static List<LyricWord> _splitIntoWordsSemantic(String text, Duration lineStart, Duration lineDuration) {
    final letters = <_CharToken>[];
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      if (ch == ' ') {
        letters.add(_CharToken(' ', false, false));
      } else if (_isPunctuation(ch)) {
        letters.add(_CharToken(ch, false, true));
      } else {
        letters.add(_CharToken(ch, true, false));
      }
    }

    if (letters.isEmpty) return [];
    if (letters.every((t) => t.isSpace)) return [];

    final visibleIndices = <int>[];
    for (int i = 0; i < letters.length; i++) {
      if (!letters[i].isSpace) visibleIndices.add(i);
    }
    if (visibleIndices.isEmpty) return [];

    final weights = <int, double>{};
    double totalWeight = 0;

    for (final idx in visibleIndices) {
      final ch = letters[idx].char;
      double w = 1.0;
      if (_isPunctuation(ch)) {
        w = ch == ',' ? 0.5 : 0.8;
      } else {
        final isLastInWord = idx == letters.length - 1 ||
            letters[idx + 1].isSpace ||
            letters[idx + 1].isPunct;
        final isFirstInWord = idx == 0 ||
            letters[idx - 1].isSpace ||
            letters[idx - 1].isPunct;
        if (isLastInWord) w += 2.0;
        if (isFirstInWord) w += 1.0;
      }
      weights[idx] = w;
      totalWeight += w;
    }

    if (totalWeight <= 0) totalWeight = 1.0;

    final result = <LyricWord>[];
    Duration currentStart = lineStart;

    for (int i = 0; i < letters.length; i++) {
      final token = letters[i];
      if (token.isSpace) {
        final prevEnd = result.isEmpty ? lineStart : result.last.endTime;
        result.add(LyricWord(
          text: ' ',
          startTime: prevEnd,
          endTime: prevEnd,
          hasComma: false,
          hasPeriod: false,
        ));
        continue;
      }

      final w = weights[i]!;
      final ratio = w / totalWeight;
      Duration charDuration = lineDuration * ratio;
      if (charDuration.inMilliseconds < 40) {
        charDuration = const Duration(milliseconds: 40);
      }

      final ch = token.char;
      result.add(LyricWord(
        text: ch,
        startTime: currentStart,
        endTime: currentStart + charDuration,
        hasComma: ch == ',',
        hasPeriod: ch == '.' || ch == '!' || ch == '?',
      ));
      currentStart += charDuration;
    }

    return result;
  }

  static bool _isPunctuation(String ch) {
    return ch == '.' || ch == ',' || ch == '!' || ch == '?' || ch == ';' || ch == ':' || ch == '-' || ch == '\'' || ch == '"';
  }
}

class _CharToken {
  final String char;
  final bool isLetter;
  final bool isPunct;
  bool get isSpace => !isLetter && !isPunct;
  const _CharToken(this.char, this.isLetter, this.isPunct);
}
