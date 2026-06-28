import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/lyrics_model.dart';

class SpicyLyricsService {
  static const String _apiUrl = 'https://api.spicylyrics.org/query';
  static const String _devUrl = 'http://localhost:3000/query';

  static bool _useDevApi = false;
  static LyricsDocument? _lastLyrics;
  static String? _lastUri;
  static final Map<String, LyricsDocument?> _cache = {};

  static void setDevMode(bool enabled) {
    _useDevApi = enabled;
  }

  static String get _endpoint => _useDevApi ? _devUrl : _apiUrl;

  static Future<LyricsDocument?> fetchLyrics(
    String uri, {
    http.Client? client,
  }) async {
    if (uri.isEmpty) return null;
    if (_lastUri == uri && _lastLyrics != null) return _lastLyrics;
    if (_cache.containsKey(uri)) return _cache[uri];

    final query = jsonEncode({
      'query':
          'query { trackLyrics(uri: "$uri") { plainLyrics syncedLyrics { time text } } }',
    });

    final http.Client httpClient = client ?? http.Client();
    try {
      final res = await httpClient
          .post(
            Uri.parse(_endpoint),
            headers: {'Content-Type': 'application/json'},
            body: query,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return _lastLyrics;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final track = json['data']?['trackLyrics'] as Map<String, dynamic>?;
      if (track == null) return _lastLyrics;

      final parsed = _parseSpicyResponse(track);
      if (parsed != null && parsed.lines.isNotEmpty) {
        _lastLyrics = parsed;
        _lastUri = uri;
        _cache[uri] = parsed;
      }
      return _lastLyrics;
    } catch (_) {
      return _lastLyrics;
    } finally {
      if (client == null) httpClient.close();
    }
  }

  static LyricsDocument? _parseSpicyResponse(Map<String, dynamic> track) {
    final plainLyrics = track['plainLyrics'] as String?;
    final syncedRaw = track['syncedLyrics'];

    final lines = <LyricLine>[];

    if (syncedRaw is List && syncedRaw.isNotEmpty) {
      for (final entry in syncedRaw) {
        final entryMap = entry as Map<String, dynamic>;
        final timeMs = (entryMap['time'] as num?)?.toInt() ?? 0;
        final text = (entryMap['text'] as String?) ?? '';
        if (text.trim().isEmpty) continue;
        lines.add(LyricLine(
          timestamp: Duration(milliseconds: timeMs),
          text: text.trim(),
        ));
      }
    } else if (plainLyrics != null && plainLyrics.isNotEmpty) {
      int i = 0;
      for (final raw in plainLyrics.split('\n')) {
        final text = raw.trim();
        if (text.isEmpty) continue;
        lines.add(LyricLine(
          timestamp: Duration(seconds: i * 3),
          text: text,
        ));
        i++;
      }
    }

    if (lines.isEmpty) return null;

    return LyricsDocument(
      rawText: plainLyrics ?? lines.map((l) => l.text).join('\n'),
      lines: lines,
      source: 'spicylyrics',
    );
  }

  static LyricsDocument? parseLrc(String rawText) {
    if (rawText.trim().isEmpty) return null;
    return LyricsDocument.parse(rawText, source: 'lrc');
  }

  static void clearCache() {
    _cache.clear();
    _lastLyrics = null;
    _lastUri = null;
  }
}
