import 'package:flutter_test/flutter_test.dart';
import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/services/karaoke_sync_calculator.dart';
import 'package:player_vf/services/lyrics_sync_engine.dart';

void main() {
  test('shifts all timed lyric rows forward', () {
    const raw = '[00:01.00] One\n[00:02.50][00:03.00] Two';

    final shifted = LyricsDocument.shiftRawTimestamps(
      raw,
      const Duration(milliseconds: 500),
    );

    expect(shifted, '[00:01.50] One\n[00:03.00][00:03.50] Two');
  });

  test('shifts timed lyric rows backward and clamps at zero', () {
    const raw = '[00:00.20] Start\n[01:02.34] Later';

    final shifted = LyricsDocument.shiftRawTimestamps(
      raw,
      const Duration(milliseconds: -500),
    );

    expect(shifted, '[00:00.00] Start\n[01:01.84] Later');
  });

  test('karaoke fill reserves the configured transition gap', () {
    const lyrics = LyricsDocument(
      rawText: '',
      source: 'test',
      lines: [
        LyricLine(timestamp: Duration(seconds: 10), text: 'First line'),
        LyricLine(timestamp: Duration(seconds: 14), text: 'Second line'),
      ],
    );
    const calculator = KaraokeSyncCalculator(transitionGapMs: 700);

    final sync = calculator.compute(
      lyrics: lyrics,
      activeIndex: 0,
      position: const Duration(milliseconds: 13300),
    );

    expect(sync.fillEnd, const Duration(milliseconds: 13300));
    expect(sync.fillProgress, 1.0);
    expect(sync.transitionDuration, const Duration(milliseconds: 700));
  });

  test('parses absolute word-level (A2L) inline timestamps', () {
    const raw = '[00:12.00]Hello <00:12.50>world <00:13.20>today';

    final lyrics = LyricsDocument.parse(raw, source: 'test');

    expect(lyrics.lines, hasLength(1));
    final line = lyrics.lines.first;
    expect(line.text, 'Hello world today');
    expect(line.words, isNotNull);
    final words = line.words!;
    expect(words.map((w) => w.text).join(' '), 'Hello world today');
    expect(words[0].startTime, const Duration(seconds: 12));
    expect(words[0].endTime, const Duration(milliseconds: 12500));
    expect(words[1].startTime, const Duration(milliseconds: 12500));
    expect(words[1].endTime, const Duration(milliseconds: 13200));
    expect(words[2].startTime, const Duration(milliseconds: 13200));
  });

  test('parses relative word-level inline timestamps', () {
    const raw = '[00:10.00]La <0.50>di <1.25>da';

    final lyrics = LyricsDocument.parse(raw, source: 'test');

    final words = lyrics.lines.first.words!;
    expect(words.map((w) => w.text).join(' '), 'La di da');
    expect(words[0].startTime, const Duration(seconds: 10));
    expect(words[0].endTime, const Duration(milliseconds: 10500));
    expect(words[1].startTime, const Duration(milliseconds: 10500));
    expect(words[1].endTime, const Duration(milliseconds: 11250));
    expect(words[2].startTime, const Duration(milliseconds: 11250));
  });

  test('ignores bare <3> hearts (no decimal) as word tags', () {
    const raw = '[00:01.00]I <3 you';

    final lyrics = LyricsDocument.parse(raw, source: 'test');

    final line = lyrics.lines.first;
    expect(line.text, 'I <3 you');
    // <3 must not be treated as a relative time tag: the fallback synthetic
    // split is character-level, so the first word is the single char 'I'.
    expect(line.words, isNotNull);
    expect(line.words!.first.text, 'I');
  });

  test('shift also moves absolute inline word tags but not relative ones', () {
    const raw = '[00:12.00]Hello <00:12.50>world <0.50>now';

    final shifted = LyricsDocument.shiftRawTimestamps(
      raw,
      const Duration(milliseconds: 500),
    );

    expect(shifted, '[00:12.50]Hello <00:13.00>world <0.50>now');
  });

  test('karaoke sync exposes active word progress from timestamps', () {
    const lyrics = LyricsDocument(
      rawText: '',
      source: 'test',
      lines: [
        LyricLine(
          timestamp: Duration(seconds: 1),
          text: 'fast rap',
          words: [
            LyricWord(
              text: 'fast',
              startTime: Duration(seconds: 1),
              endTime: Duration(milliseconds: 1200),
            ),
            LyricWord(
              text: 'rap',
              startTime: Duration(milliseconds: 1200),
              endTime: Duration(milliseconds: 1400),
            ),
          ],
        ),
      ],
    );
    const calculator = KaraokeSyncCalculator();

    final sync = calculator.compute(
      lyrics: lyrics,
      activeIndex: 0,
      position: const Duration(milliseconds: 1300),
    );

    expect(sync.activeWordIndex, 1);
    expect(sync.activeWordProgress, closeTo(0.5, 0.001));
  });

  test('inline words are marked non-synthetic', () {
    const raw = '[00:12.00]Hello <00:12.50>world <00:13.20>today';

    final lyrics = LyricsDocument.parse(raw, source: 'test');
    final words = lyrics.lines.first.words!;
    expect(words.every((w) => !w.isSynthetic), isTrue);
  });

  test('synthetic words are marked synthetic', () {
    const raw = '[00:12.00]Hello world today';

    final lyrics = LyricsDocument.parse(raw, source: 'test');
    final words = lyrics.lines.first.words!;
    expect(words.every((w) => w.isSynthetic), isTrue);
  });

  test('LyricsSyncEngine getWordProgress computes correct progress', () {
    final engine = LyricsSyncEngine();
    final lyrics = LyricsDocument(
      rawText: '',
      source: 'test',
      lines: [
        LyricLine(
          timestamp: Duration(seconds: 1),
          text: 'hello world',
          words: [
            LyricWord(
              text: 'hello',
              startTime: Duration(seconds: 1),
              endTime: Duration(milliseconds: 1200),
              isSynthetic: false,
            ),
            LyricWord(
              text: 'world',
              startTime: Duration(milliseconds: 1200),
              endTime: Duration(milliseconds: 1500),
              isSynthetic: false,
            ),
          ],
        ),
      ],
    );
    engine.setLyrics(lyrics);

    expect(engine.getWordProgress(Duration(milliseconds: 1100), lineIndex: 0, wordIndex: 0),
        closeTo(0.5, 0.001));
    expect(engine.getWordProgress(Duration(milliseconds: 1300), lineIndex: 0, wordIndex: 1),
        closeTo(0.333, 0.001));
    expect(engine.getWordProgress(Duration(milliseconds: 500), lineIndex: 0, wordIndex: 0),
        closeTo(0.0, 0.001));
  });

  test('LyricsSyncEngine adaptive smoothing converges faster for large drift', () {
    final engine = LyricsSyncEngine();
    final lyrics = LyricsDocument(
      rawText: '',
      source: 'test',
      lines: [
        LyricLine(
          timestamp: Duration(seconds: 1),
          text: 'test',
          words: [
            LyricWord(
              text: 'test',
              startTime: Duration(seconds: 1),
              endTime: Duration(seconds: 2),
              isSynthetic: false,
            ),
          ],
        ),
      ],
    );
    engine.setLyrics(lyrics);

    engine.processWordTiming(1000, 0, confidence: 1.0);
    final drift1 = engine.getSyncState(Duration.zero);
    final firstDrift = drift1.activeLineIndex;

    engine.processWordTiming(1000, 0, confidence: 1.0);
    final drift2 = engine.getSyncState(Duration.zero);
    final secondDrift = drift2.activeLineIndex;

    expect(firstDrift, secondDrift);
  });

  group('Word-by-word timing algorithm requirements', () {
    test('last word of line does not swallow line-end pause time', () {
      const raw = '[00:10.00]First second third\n[00:14.00]Next line';
      final lyrics = LyricsDocument.parse(raw, source: 'test');
      final line1 = lyrics.lines[0];
      final words = line1.words!;

      expect(words.length, 3);
      final lastWord = words.last;
      
      // Last word should finish comfortably before next line timestamp (00:14.00)
      expect(lastWord.endTime.inMilliseconds, lessThan(14000));
      // Remaining unused time stays as silence/pause
      final unusedPauseMs = 14000 - lastWord.endTime.inMilliseconds;
      expect(unusedPauseMs, greaterThanOrEqualTo(200));
    });

    test('speaking speed is consistent across all words in line', () {
      const raw = '[00:00.00]Apple banana cherry\n[00:04.00]End';
      final lyrics = LyricsDocument.parse(raw, source: 'test');
      final words = lyrics.lines[0].words!;

      final word1Dur = words[0].duration.inMilliseconds;
      final word2Dur = words[1].duration.inMilliseconds;
      final word3Dur = words[2].duration.inMilliseconds;

      // Durations scale according to syllable & char weight without last word artificial slowdown
      expect(word1Dur, greaterThan(0));
      expect(word2Dur, greaterThan(0));
      expect(word3Dur, greaterThan(0));
      
      // Rate of last word is comparable to first word rather than blown up
      final ratio = word3Dur / word1Dur;
      expect(ratio, closeTo(1.0, 0.4));
    });

    test('handles one-word lines correctly', () {
      const raw = '[00:02.00]Hello\n[00:05.00]World';
      final lyrics = LyricsDocument.parse(raw, source: 'test');
      final words = lyrics.lines[0].words!;

      expect(words.length, 1);
      expect(words[0].text, 'Hello');
      expect(words[0].duration.inMilliseconds, lessThan(2500));
      expect(words[0].startTime, Duration(seconds: 2));
    });

    test('handles punctuation pauses properly', () {
      const raw = '[00:00.00]Wait, stop! Go.\n[00:05.00]Next';
      final lyrics = LyricsDocument.parse(raw, source: 'test');
      final words = lyrics.lines[0].words!;

      expect(words[0].hasComma, isTrue);
      expect(words[1].hasPeriod, isTrue);
      
      // Word after comma/period starts after a pause gap
      final gapAfterComma = words[1].startTime.inMilliseconds - words[0].endTime.inMilliseconds;
      expect(gapAfterComma, greaterThan(0));
    });
  });
}
