import 'dart:math' as math;
import 'package:player_vf/models/lyrics_model.dart';

class LyricsParser {
  static final RegExp _lrcTimePattern =
  RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final RegExp _metadataPattern = RegExp(r'^\[[a-zA-Z]+:.*\]$');

  // Word-level inline tags — absolute <mm:ss.xx> or relative <0.50>
  static final RegExp _inlineWordTimePattern =
  RegExp(r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>');
  static final RegExp _inlineWordRelativePattern =
  RegExp(r'<(\d+)\.(\d{1,3})>');

  // ─── Public entry point ────────────────────────────────────────────────────

  static LyricsDocument parse(String rawText, {required String source}) {
    if (rawText.contains('<tt') || rawText.contains('<ttml')) {
      return _parseTtml(rawText, source: source);
    }
    if (_lrcTimePattern.hasMatch(rawText)) {
      return _parseLrc(rawText, source: source);
    }
    return _parsePlainText(rawText, source: source);
  }

  // ─── LRC parser ───────────────────────────────────────────────────────────

  static LyricsDocument _parseLrc(String rawText, {required String source}) {
    final parsedLines = <LyricLine>[];

    for (final rawLine in rawText.replaceAll('\r\n', '\n').split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || _metadataPattern.hasMatch(line)) continue;

      final matches = _lrcTimePattern.allMatches(line).toList();
      final text = line.replaceAll(_lrcTimePattern, '').trim();

      if (matches.isEmpty) {
        if (text.isNotEmpty) parsedLines.add(LyricLine(timestamp: null, text: text));
        continue;
      }

      for (final match in matches) {
        if (text.isEmpty) continue;
        final timestamp = _parseTimestamp(match);
        final cleanText = text
            .replaceAll(_inlineWordTimePattern, '')
            .replaceAll(_inlineWordRelativePattern, '')
            .trim();
        // lineEnd placeholder — corrected to real next-line time in
        // _generateLineEndingsAndWords via fillTarget clamping.
        final words = _parseInlineWords(text, timestamp, timestamp + const Duration(seconds: 5));
        parsedLines.add(LyricLine(timestamp: timestamp, text: cleanText, words: words));
      }
    }

    parsedLines.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return 1;
      if (b.timestamp == null) return -1;
      return a.timestamp!.compareTo(b.timestamp!);
    });

    return LyricsDocument(
      rawText: rawText,
      lines: _generateLineEndingsAndWords(_mergeTranslations(parsedLines)),
      source: source,
    );
  }

  // ─── Plain-text parser ────────────────────────────────────────────────────

  static LyricsDocument _parsePlainText(String rawText, {required String source}) {
    final lines = rawText
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) => LyricLine(timestamp: null, text: l.trim()))
        .toList();
    return LyricsDocument(rawText: rawText, lines: lines, source: source);
  }

  // ─── TTML parser ──────────────────────────────────────────────────────────

  static LyricsDocument _parseTtml(String rawText, {required String source}) {
    final parsedLines = <LyricLine>[];

    final pPattern = RegExp(r'<p\s+([^>]*?)>(.*?)</p>', caseSensitive: false, dotAll: true);
    final spanPattern = RegExp(
      r'<span\s+begin="([^"]+)"\s+end="([^"]+)"[^>]*>(.*?)</span>',
      caseSensitive: false,
      dotAll: true,
    );

    for (final pMatch in pPattern.allMatches(rawText)) {
      final pAttrs = pMatch.group(1) ?? '';
      final pContent = pMatch.group(2) ?? '';

      final beginMatch = RegExp(r'begin="([^"]+)"').firstMatch(pAttrs);
      final endMatch = RegExp(r'end="([^"]+)"').firstMatch(pAttrs);
      if (beginMatch == null) continue;

      final lineStart = _parseTtmlTime(beginMatch.group(1)!);
      final lineEnd = endMatch != null ? _parseTtmlTime(endMatch.group(1)!) : null;
      if (lineStart == null) continue;

      final words = <LyricWord>[];
      final fullText = StringBuffer();

      for (final spanMatch in spanPattern.allMatches(pContent)) {
        final spanText = spanMatch.group(3)?.trim() ?? '';
        if (spanText.isEmpty) continue;
        final wordStart = _parseTtmlTime(spanMatch.group(1)!);
        final wordEnd = _parseTtmlTime(spanMatch.group(2)!);
        if (wordStart == null) continue;
        fullText.write(spanText);
        words.add(LyricWord(
          text: spanText,
          startTime: wordStart,
          endTime: wordEnd ?? wordStart + const Duration(milliseconds: 500),
          isSynthetic: false,
        ));
      }

      if (words.isEmpty) {
        final plain = pContent.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        if (plain.isNotEmpty) {
          words.add(LyricWord(
            text: plain,
            startTime: lineStart,
            endTime: lineEnd ?? lineStart + const Duration(seconds: 5),
            isSynthetic: true,
          ));
          fullText.write(plain);
        }
      }

      final text = fullText.toString().trim();
      if (text.isNotEmpty) {
        parsedLines.add(LyricLine(
          timestamp: lineStart,
          endTime: lineEnd,
          text: text,
          words: words.isNotEmpty ? words : null,
        ));
      }
    }

    // Fallback: simpler TTML pattern
    if (parsedLines.isEmpty) {
      final simple = RegExp(
        r'<p\s+begin="([^"]+)"\s+end="([^"]+)"[^>]*>([^<]*(?:<[^>]*>[^<]*)*)</p>',
        caseSensitive: false,
        dotAll: true,
      );
      for (final m in simple.allMatches(rawText)) {
        final start = _parseTtmlTime(m.group(1)!);
        final end = _parseTtmlTime(m.group(2)!);
        final text = m.group(3)?.replaceAll(RegExp(r'<[^>]*>'), '').trim() ?? '';
        if (text.isNotEmpty && start != null) {
          parsedLines.add(LyricLine(timestamp: start, endTime: end, text: text));
        }
      }
    }

    if (parsedLines.isEmpty) {
      return LyricsDocument(
        rawText: rawText,
        lines: [const LyricLine(timestamp: null, text: 'TTML parse failed')],
        source: source,
      );
    }

    return LyricsDocument(rawText: rawText, lines: parsedLines, source: source);
  }

  // ─── Timing helpers ───────────────────────────────────────────────────────

  static Duration? _parseTtmlTime(String t) {
    if (t.isEmpty) return null;
    final parts = t.split(':');
    try {
      if (parts.length == 3) {
        final h = int.parse(parts[0]);
        final m = int.parse(parts[1]);
        final dot = parts[2].indexOf('.');
        final s = dot >= 0 ? int.parse(parts[2].substring(0, dot)) : int.parse(parts[2]);
        final ms = dot >= 0 ? _parseFraction(parts[2].substring(dot + 1)) : 0;
        return Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);
      } else if (parts.length == 2) {
        final m = int.parse(parts[0]);
        final dot = parts[1].indexOf('.');
        final s = dot >= 0 ? int.parse(parts[1].substring(0, dot)) : int.parse(parts[1]);
        final ms = dot >= 0 ? _parseFraction(parts[1].substring(dot + 1)) : 0;
        return Duration(minutes: m, seconds: s, milliseconds: ms);
      } else {
        final dot = parts[0].indexOf('.');
        final s = dot >= 0 ? int.parse(parts[0].substring(0, dot)) : int.parse(parts[0]);
        final ms = dot >= 0 ? _parseFraction(parts[0].substring(dot + 1)) : 0;
        return Duration(seconds: s, milliseconds: ms);
      }
    } catch (_) {
      return null;
    }
  }

  static Duration _parseTimestamp(Match match) {
    final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
    final ms = _parseFraction(match.group(3) ?? '0');
    return Duration(minutes: minutes, seconds: seconds, milliseconds: ms);
  }

  static int _parseFraction(String f) {
    if (f.isEmpty || f == '0') return 0;
    return f.length == 1
        ? int.parse(f) * 100
        : f.length == 2
        ? int.parse(f) * 10
        : int.parse(f.padRight(3, '0').substring(0, 3));
  }

  // ─── Inline word-time parser ──────────────────────────────────────────────

  /// Parses `<mm:ss.xx>` or `<s.ms>` inline tags into per-word timings.
  /// The last word's endTime is a placeholder; _generateLineEndingsAndWords
  /// overwrites it with the real fillTarget.
  static List<LyricWord>? _parseInlineWords(
      String rawText,
      Duration lineStart,
      Duration lineEnd,
      ) {
    final absTags = _inlineWordTimePattern.allMatches(rawText).toList();
    final relTags = _inlineWordRelativePattern.allMatches(rawText).toList();
    if (absTags.isEmpty && relTags.isEmpty) return null;

    final useAbsolute = absTags.isNotEmpty;
    final tags = useAbsolute ? absTags : relTags;

    final segments = <String>[];
    final starts = <Duration>[];
    int cursor = 0;
    Duration nextStart = lineStart;

    for (final tag in tags) {
      segments.add(rawText.substring(cursor, tag.start).trim());
      cursor = tag.end;
      starts.add(nextStart);
      final tagTime = useAbsolute
          ? _parseTimestamp(tag)
          : lineStart + Duration(
        seconds: int.tryParse(tag.group(1) ?? '0') ?? 0,
        milliseconds: _parseFraction(tag.group(2) ?? '0'),
      );
      if (tagTime > nextStart) nextStart = tagTime;
    }
    segments.add(rawText.substring(cursor).trim());
    starts.add(nextStart);

    final words = <LyricWord>[];
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      if (seg.isEmpty) continue;
      final start = starts[i];
      final end = i < segments.length - 1 ? starts[i + 1] : lineEnd;
      words.add(LyricWord(
        text: seg,
        startTime: start,
        endTime: end > start ? end : start + const Duration(milliseconds: 80),
        isSynthetic: false,
      ));
    }
    return words.isEmpty ? null : words;
  }

  // ─── Translation merge ────────────────────────────────────────────────────

  static List<LyricLine> _mergeTranslations(List<LyricLine> sorted) {
    if (sorted.isEmpty) return sorted;
    final result = <LyricLine>[];
    LyricLine? current;
    for (final line in sorted) {
      if (current == null) { current = line; continue; }
      if (current.timestamp != null && line.timestamp != null) {
        final diff = (line.timestamp! - current.timestamp!).inMilliseconds.abs();
        if (diff < 50) { current = current.copyWith(translation: line.text); continue; }
      }
      result.add(current);
      current = line;
    }
    if (current != null) result.add(current);
    return result;
  }

  // ─── Line endings + word timing ───────────────────────────────────────────

  static List<LyricLine> _generateLineEndingsAndWords(List<LyricLine> lines) {
    final result = <LyricLine>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.timestamp == null) { result.add(line); continue; }

      // maxDuration: gap to next line, capped at 10s for long instrumental breaks.
      // For last line: 7s default.
      Duration maxDuration;
      if (i < lines.length - 1 && lines[i + 1].timestamp != null) {
        maxDuration = lines[i + 1].timestamp! - line.timestamp!;
        if (maxDuration.inMilliseconds > 15000) maxDuration = const Duration(seconds: 10);
      } else {
        maxDuration = const Duration(seconds: 7);
      }

      // ── fillTarget ────────────────────────────────────────────────────────
      // ALWAYS derived from the already-capped maxDuration, NOT from raw
      // nextTimestamp. Using nextTimestamp directly caused 13+ second slow fills
      // for lines before instrumental breaks (gap > 15s but target was uncapped).
      final fillTarget = line.timestamp! + maxDuration;
      // ─────────────────────────────────────────────────────────────────────

      var words = line.words;
      if (words == null) {
        words = _generateWordTimingsForLine(
          lineText: line.text,
          lineStart: line.timestamp!,
          maxDuration: maxDuration,
        );
      }

      // Clamp last word endTime to fillTarget — both directions.
      // Inline-timed lyrics get lineStart+5s as a placeholder for the last
      // word; this replaces it with the real capped end time. Synthetic words
      // also get extended to fill the row completely.
      if (words.isNotEmpty && words.last.endTime != fillTarget) {
        final last = words.last;
        words = [
          ...words.sublist(0, words.length - 1),
          LyricWord(
            text: last.text,
            startTime: last.startTime,
            endTime: fillTarget,
            hasComma: last.hasComma,
            hasPeriod: last.hasPeriod,
            isSynthetic: last.isSynthetic,
          ),
        ];
      }

      result.add(line.copyWith(endTime: fillTarget, words: words));
    }
    return result;
  }

  // ─── Synthetic word timing generator ──────────────────────────────────────

  /// Distributes [maxDuration] proportionally across words using syllable +
  /// character weights at ~75 ms/unit (singing speed). The last word's endTime
  /// is overwritten by _generateLineEndingsAndWords to fillTarget anyway, so no
  /// reserved trailing pause is needed here.
  static List<LyricWord> _generateWordTimingsForLine({
    required String lineText,
    required Duration lineStart,
    required Duration maxDuration,
  }) {
    final tokens = lineText.trim().split(RegExp(r'\s+'));
    if (tokens.isEmpty || (tokens.length == 1 && tokens[0].isEmpty)) return [];

    // Compute per-token weights
    final weights = <double>[];
    final pauses = <double>[];
    double total = 0;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final syl = _estimateSyllables(t);
      final ch = t.replaceAll(RegExp(r'[^\w]'), '').length;
      double w = (syl * 1.8) + (ch * 0.4);
      if (w < 1.0) w = 1.0;

      final comma = t.contains(',') || t.contains(';') || t.contains(':');
      final period = t.contains('.') || t.contains('!') || t.contains('?');
      if (comma) w += 0.3;
      if (period) w += 0.5;
      weights.add(w);
      total += w;

      double p = 0;
      if (i < tokens.length - 1) {
        p = comma ? 0.5 : period ? 0.8 : 0.15;
      }
      pauses.add(p);
    }

    final windowMs = maxDuration.inMilliseconds;
    final naturalMs = (total * 75.0).round();
    final activeMs = naturalMs.clamp(150, windowMs).toInt();
    final msPerUnit = total > 0 ? activeMs / total : 75.0;

    final result = <LyricWord>[];
    Duration ptr = lineStart;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      final wordMs = math.max(80, (weights[i] * msPerUnit).round());
      final wordEnd = ptr + Duration(milliseconds: wordMs);
      result.add(LyricWord(
        text: t,
        startTime: ptr,
        endTime: wordEnd,
        hasComma: t.contains(',') || t.contains(';') || t.contains(':'),
        hasPeriod: t.contains('.') || t.contains('!') || t.contains('?'),
        isSynthetic: true,
      ));
      ptr = wordEnd + Duration(milliseconds: (pauses[i] * msPerUnit).round());
    }

    return result;
  }

  static int _estimateSyllables(String word) {
    final clean = word.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (clean.length <= 3) return 1;
    final matches = RegExp(r'[aeiouy]+').allMatches(clean).length;
    int count = matches;
    if (clean.endsWith('e') && !clean.endsWith('le') && count > 1) count--;
    return math.max(1, count);
  }
}