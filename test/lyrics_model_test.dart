import 'package:flutter_test/flutter_test.dart';
import 'package:player_vf/models/lyrics_model.dart';

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
}
