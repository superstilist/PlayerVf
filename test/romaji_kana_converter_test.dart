import 'package:flutter_test/flutter_test.dart';
import 'package:player_vf/utils/romaji_kana_converter.dart';

void main() {
  test('generates clean romaji from hiragana lyrics', () {
    expect(
      RomajiKanaConverter.generatedRomajiForLine('きっと だいじょうぶ'),
      'kitto daijoubu',
    );
  });

  test('generates clean romaji from katakana lyrics', () {
    expect(
      RomajiKanaConverter.generatedRomajiForLine('アイドル'),
      'aidoru',
    );
  });

  test('keeps long vowel sound for katakana lyrics', () {
    expect(
      RomajiKanaConverter.generatedRomajiForLine('スーパー スター'),
      'suupaa sutaa',
    );
  });

  test('does not generate hiragana from latin romaji lyrics', () {
    expect(
      RomajiKanaConverter.generatedRomajiForLine('kitto daijoubu'),
      '',
    );
  });

  test('does not copy kanji into generated romaji line', () {
    final romaji = RomajiKanaConverter.generatedRomajiForLine('君の こころ が 光る');

    expect(romaji, 'no kokoro ga ru');
    expect(RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(romaji), isFalse);
  });
}
