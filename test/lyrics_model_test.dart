import 'package:flutter_test/flutter_test.dart';
import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/services/karaoke_sync_calculator.dart';

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
}
