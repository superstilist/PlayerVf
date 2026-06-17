class RomajiKanaConverter {
  static final Map<String, String> _cache = {};

  static String generatedKanaForLine(String input) {
    return generatedRomajiForLine(input);
  }

  static String generatedTranscriptionForLine(String input) {
    return generatedRomajiForLine(input);
  }

  static String generatedRomajiForLine(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) return '';
    return _cache.putIfAbsent(normalized, () {
      if (!_hasKana(normalized)) return '';
      final converted = _kanaToRomaji(normalized);
      return _isUsefulRomajiConversion(normalized, converted) ? converted : '';
    });
  }

  static bool _hasKana(String input) {
    return RegExp(r'[\u3040-\u30ff]').hasMatch(input);
  }

  static bool _isUsefulRomajiConversion(String source, String converted) {
    if (converted == source || converted.trim().isEmpty) return false;
    final sourceKana = RegExp(r'[\u3040-\u30ff]').allMatches(source).length;
    final convertedLetters = RegExp(r'[A-Za-z]').allMatches(converted).length;
    return sourceKana >= 2 && convertedLetters >= 2;
  }

  static String _kanaToRomaji(String input) {
    final buffer = StringBuffer();
    var index = 0;

    while (index < input.length) {
      final current = input[index];
      final next = index + 1 < input.length ? input[index + 1] : '';

      if (current == 'っ' || current == 'ッ') {
        final lookahead = _kanaPairToRomaji(
                next, index + 2 < input.length ? input[index + 2] : '') ??
            _kanaToRomajiMap[next];
        if (lookahead != null && lookahead.isNotEmpty) {
          buffer.write(lookahead[0]);
        }
        index++;
        continue;
      }

      if (_isLongVowelMark(current)) {
        _writeRomaji(buffer, _lastRomajiVowel(buffer.toString()) ?? '-');
        index++;
        continue;
      }

      final pair = _kanaPairToRomaji(current, next);
      if (pair != null) {
        _writeRomaji(buffer, pair);
        index += 2;
        continue;
      }

      final romaji = _kanaToRomajiMap[current];
      if (romaji != null) {
        final needsApostrophe = (current == 'ん' || current == 'ン') &&
            next.isNotEmpty &&
            _romajiStartsWithVowelOrY(next);
        _writeRomaji(buffer, needsApostrophe ? "n'" : romaji);
      } else if (_isCjkCharacter(current)) {
        _writeSeparator(buffer);
      } else if (_isAllowedRomajiSeparator(current)) {
        _writeSeparator(buffer);
      } else if (_isAsciiText(current)) {
        buffer.write(current);
      } else {
        _writeSeparator(buffer);
      }
      index++;
    }

    return buffer
        .toString()
        .replaceAll(RegExp(r"[^A-Za-z0-9\s,.'!?;:()&/\-]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _kanaPairToRomaji(String current, String next) {
    if (next.isEmpty) return null;
    return _kanaToRomajiMap['$current$next'];
  }

  static void _writeRomaji(StringBuffer buffer, String romaji) {
    final text = buffer.toString();
    if (text.isNotEmpty && _lastNeedsRomajiSeparator(text)) {
      buffer.write(' ');
    }
    buffer.write(romaji);
  }

  static bool _lastNeedsRomajiSeparator(String text) {
    final last = text[text.length - 1];
    return RegExp(r'[\u3400-\u9fff0-9]').hasMatch(last);
  }

  static void _writeSeparator(StringBuffer buffer) {
    if (buffer.isEmpty) return;
    final text = buffer.toString();
    if (!text.endsWith(' ')) buffer.write(' ');
  }

  static bool _isCjkCharacter(String char) {
    return RegExp(r'[\u3040-\u30ff\u3400-\u9fff]').hasMatch(char);
  }

  static bool _isAllowedRomajiSeparator(String char) {
    return RegExp(r"[\s,.'!?;:()&/\-]").hasMatch(char);
  }

  static bool _isAsciiText(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x7a;
  }

  static bool _romajiStartsWithVowelOrY(String kana) {
    final romaji = _kanaToRomajiMap[kana];
    if (romaji == null || romaji.isEmpty) return false;
    return _isVowel(romaji[0]) || romaji[0] == 'y';
  }

  static bool _isLongVowelMark(String char) => char == 'ー';

  static String? _lastRomajiVowel(String value) {
    for (var i = value.length - 1; i >= 0; i--) {
      final char = value[i].toLowerCase();
      if (_isVowel(char)) return char;
    }
    return null;
  }

  static bool _isVowel(String char) =>
      const ['a', 'e', 'i', 'o', 'u'].contains(char);

  static const Map<String, String> _kanaToRomajiMap = {
    'あ': 'a',
    'い': 'i',
    'う': 'u',
    'え': 'e',
    'お': 'o',
    'ぁ': 'a',
    'ぃ': 'i',
    'ぅ': 'u',
    'ぇ': 'e',
    'ぉ': 'o',
    'か': 'ka',
    'き': 'ki',
    'く': 'ku',
    'け': 'ke',
    'こ': 'ko',
    'きゃ': 'kya',
    'きゅ': 'kyu',
    'きょ': 'kyo',
    'さ': 'sa',
    'し': 'shi',
    'す': 'su',
    'せ': 'se',
    'そ': 'so',
    'しゃ': 'sha',
    'しゅ': 'shu',
    'しょ': 'sho',
    'た': 'ta',
    'ち': 'chi',
    'つ': 'tsu',
    'て': 'te',
    'と': 'to',
    'ちゃ': 'cha',
    'ちゅ': 'chu',
    'ちょ': 'cho',
    'な': 'na',
    'に': 'ni',
    'ぬ': 'nu',
    'ね': 'ne',
    'の': 'no',
    'にゃ': 'nya',
    'にゅ': 'nyu',
    'にょ': 'nyo',
    'は': 'ha',
    'ひ': 'hi',
    'ふ': 'fu',
    'へ': 'he',
    'ほ': 'ho',
    'ひゃ': 'hya',
    'ひゅ': 'hyu',
    'ひょ': 'hyo',
    'ま': 'ma',
    'み': 'mi',
    'む': 'mu',
    'め': 'me',
    'も': 'mo',
    'みゃ': 'mya',
    'みゅ': 'myu',
    'みょ': 'myo',
    'や': 'ya',
    'ゆ': 'yu',
    'よ': 'yo',
    'ゃ': 'ya',
    'ゅ': 'yu',
    'ょ': 'yo',
    'ら': 'ra',
    'り': 'ri',
    'る': 'ru',
    'れ': 're',
    'ろ': 'ro',
    'りゃ': 'rya',
    'りゅ': 'ryu',
    'りょ': 'ryo',
    'わ': 'wa',
    'を': 'wo',
    'ん': 'n',
    'が': 'ga',
    'ぎ': 'gi',
    'ぐ': 'gu',
    'げ': 'ge',
    'ご': 'go',
    'ぎゃ': 'gya',
    'ぎゅ': 'gyu',
    'ぎょ': 'gyo',
    'ざ': 'za',
    'じ': 'ji',
    'ず': 'zu',
    'ぜ': 'ze',
    'ぞ': 'zo',
    'じゃ': 'ja',
    'じゅ': 'ju',
    'じょ': 'jo',
    'だ': 'da',
    'ぢ': 'ji',
    'づ': 'zu',
    'で': 'de',
    'ど': 'do',
    'ば': 'ba',
    'び': 'bi',
    'ぶ': 'bu',
    'べ': 'be',
    'ぼ': 'bo',
    'びゃ': 'bya',
    'びゅ': 'byu',
    'びょ': 'byo',
    'ぱ': 'pa',
    'ぴ': 'pi',
    'ぷ': 'pu',
    'ぺ': 'pe',
    'ぽ': 'po',
    'ぴゃ': 'pya',
    'ぴゅ': 'pyu',
    'ぴょ': 'pyo',
    'ゔ': 'vu',
    'ゔぁ': 'va',
    'ゔぃ': 'vi',
    'ゔぇ': 've',
    'ゔぉ': 'vo',
    'ア': 'a',
    'イ': 'i',
    'ウ': 'u',
    'エ': 'e',
    'オ': 'o',
    'カ': 'ka',
    'キ': 'ki',
    'ク': 'ku',
    'ケ': 'ke',
    'コ': 'ko',
    'キャ': 'kya',
    'キュ': 'kyu',
    'キョ': 'kyo',
    'サ': 'sa',
    'シ': 'shi',
    'ス': 'su',
    'セ': 'se',
    'ソ': 'so',
    'シャ': 'sha',
    'シュ': 'shu',
    'ショ': 'sho',
    'タ': 'ta',
    'チ': 'chi',
    'ツ': 'tsu',
    'テ': 'te',
    'ト': 'to',
    'チャ': 'cha',
    'チュ': 'chu',
    'チョ': 'cho',
    'ナ': 'na',
    'ニ': 'ni',
    'ヌ': 'nu',
    'ネ': 'ne',
    'ノ': 'no',
    'ニャ': 'nya',
    'ニュ': 'nyu',
    'ニョ': 'nyo',
    'ハ': 'ha',
    'ヒ': 'hi',
    'フ': 'fu',
    'ヘ': 'he',
    'ホ': 'ho',
    'ヒャ': 'hya',
    'ヒュ': 'hyu',
    'ヒョ': 'hyo',
    'マ': 'ma',
    'ミ': 'mi',
    'ム': 'mu',
    'メ': 'me',
    'モ': 'mo',
    'ミャ': 'mya',
    'ミュ': 'myu',
    'ミョ': 'myo',
    'ヤ': 'ya',
    'ユ': 'yu',
    'ヨ': 'yo',
    'ラ': 'ra',
    'リ': 'ri',
    'ル': 'ru',
    'レ': 're',
    'ロ': 'ro',
    'リャ': 'rya',
    'リュ': 'ryu',
    'リョ': 'ryo',
    'ワ': 'wa',
    'ヲ': 'wo',
    'ン': 'n',
    'ガ': 'ga',
    'ギ': 'gi',
    'グ': 'gu',
    'ゲ': 'ge',
    'ゴ': 'go',
    'ギャ': 'gya',
    'ギュ': 'gyu',
    'ギョ': 'gyo',
    'ザ': 'za',
    'ジ': 'ji',
    'ズ': 'zu',
    'ゼ': 'ze',
    'ゾ': 'zo',
    'ジャ': 'ja',
    'ジュ': 'ju',
    'ジョ': 'jo',
    'ダ': 'da',
    'ヂ': 'ji',
    'ヅ': 'zu',
    'デ': 'de',
    'ド': 'do',
    'バ': 'ba',
    'ビ': 'bi',
    'ブ': 'bu',
    'ベ': 'be',
    'ボ': 'bo',
    'ビャ': 'bya',
    'ビュ': 'byu',
    'ビョ': 'byo',
    'パ': 'pa',
    'ピ': 'pi',
    'プ': 'pu',
    'ペ': 'pe',
    'ポ': 'po',
    'ピャ': 'pya',
    'ピュ': 'pyu',
    'ピョ': 'pyo',
  };
}
