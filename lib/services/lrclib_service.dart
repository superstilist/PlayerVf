import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/utils/lyrics_parser.dart';

class LrcLibService {
  static const String _baseUrl = 'https://lrclib.net/api';
  static const _userAgent = 'PlayerVF/1.0.0 (https://github.com/superstilist/PlayerVf)';
  static const _connectTimeout = Duration(seconds: 8);
  static const _requestTimeout = Duration(seconds: 12);

  static final Map<String, LyricsDocument> _cache = {};

  static Future<LyricsDocument?> fetchLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    final cacheKey = '$trackName|$artistName|$albumName|$durationSeconds';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _connectTimeout;

      // --- Try /get (exact match) ---
      final params = <String, String>{
        'track_name': trackName.trim(),
        'artist_name': artistName.trim(),
        if (albumName != null && albumName.trim().isNotEmpty)
          'album_name': albumName.trim(),
        if (durationSeconds != null && durationSeconds > 0)
          'duration': durationSeconds.toString(),
      };

      final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: params);
      debugPrint('LrcLib: GET $uri');

      final getResult = await _fetchJson(client, uri);
      if (getResult != null) {
        final doc = _parseResponse(getResult, 'LRCLIB (Synced)');
        if (doc != null) {
          _cache[cacheKey] = doc;
          return doc;
        }
        debugPrint('LrcLib: /get returned 200 but no lyrics, trying /search');
      }

      // --- Fall back to /search (fuzzy) ---
      return _searchLyrics(client, trackName, artistName, albumName, durationSeconds);
    } catch (e) {
      debugPrint('LrcLib: fetch error: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  static Future<LyricsDocument?> _searchLyrics(
    HttpClient client,
    String trackName,
    String artistName,
    String? albumName,
    int? durationSeconds,
  ) async {
    try {
      final query = [trackName, artistName]
          .where((s) => s.trim().isNotEmpty)
          .join(' ')
          .trim();
      if (query.isEmpty) return null;

      final uri =
          Uri.parse('$_baseUrl/search').replace(queryParameters: {'q': query});
      debugPrint('LrcLib: SEARCH $uri');

      final searchResult = await _fetchJson(client, uri);
      if (searchResult == null) return null;

      final List<dynamic> results = searchResult;
      if (results.isEmpty) {
        debugPrint('LrcLib: /search returned 0 results');
        return null;
      }
      debugPrint('LrcLib: /search returned ${results.length} results');

      // Sort by duration proximity if available
      if (durationSeconds != null && durationSeconds > 0) {
        results.sort((a, b) {
          final aDur = (a['duration'] as num?)?.round() ?? 0;
          final bDur = (b['duration'] as num?)?.round() ?? 0;
          return (aDur - durationSeconds)
              .abs()
              .compareTo((bDur - durationSeconds).abs());
        });
      }

      // Prefer synced lyrics from closest-duration result
      for (final result in results) {
        final syncedLyrics = result['syncedLyrics'] as String?;
        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          final t = result['trackName'] ?? '?';
          final a = result['artistName'] ?? '?';
          debugPrint('LrcLib: found synced for "$t" by "$a"');
          final doc = LyricsParser.parse(syncedLyrics,
              source: 'LRCLIB (Search Synced)');
          _cache['$trackName|$artistName|$albumName|$durationSeconds'] = doc;
          return doc;
        }
      }

      // Fall back to plain text
      final plainLyrics = results.first['plainLyrics'] as String?;
      if (plainLyrics != null && plainLyrics.isNotEmpty) {
        final doc = LyricsParser.parse(plainLyrics,
            source: 'LRCLIB (Search Plain)');
        _cache['$trackName|$artistName|$albumName|$durationSeconds'] = doc;
        return doc;
      }
      debugPrint('LrcLib: results had no lyrics');
    } catch (e) {
      debugPrint('LrcLib: search error: $e');
    }
    return null;
  }

  static Future<dynamic> _fetchJson(
      HttpClient client, Uri uri) async {
    try {
      final request = await client
          .getUrl(uri)
          .timeout(_connectTimeout)
          .catchError((e) => throw TimeoutException('connect timeout: $e'));

      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');

      final response = await request.close().timeout(_requestTimeout);
      final status = response.statusCode;
      debugPrint('LrcLib: HTTP $status from ${uri.path}');

      if (status != 200) {
        debugPrint('LrcLib: non-200 status=$status');
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      if (body.trim().isEmpty) {
        debugPrint('LrcLib: empty response body');
        return null;
      }

      final decoded = json.decode(body);
      return decoded;
    } on TimeoutException catch (e) {
      debugPrint('LrcLib: timeout: $e');
    } on HttpException catch (e) {
      debugPrint('LrcLib: HTTP error: $e');
    } catch (e) {
      debugPrint('LrcLib: fetch error: $e');
    }
    return null;
  }

  static LyricsDocument? _parseResponse(
      dynamic data, String source) {
    try {
      if (data is! Map) return null;
      final syncedLyrics = data['syncedLyrics'] as String?;
      if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
        return LyricsParser.parse(syncedLyrics, source: source);
      }
      final plainLyrics = data['plainLyrics'] as String?;
      if (plainLyrics != null && plainLyrics.isNotEmpty) {
        return LyricsParser.parse(plainLyrics,
            source: source.replaceAll('Synced', 'Plain Text'));
      }
    } catch (e) {
      debugPrint('LrcLib: parse error: $e');
    }
    return null;
  }

  static Future<List<LrclibLyrics>> searchResults({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _connectTimeout;
      final query = [trackName, artistName]
          .where((s) => s.trim().isNotEmpty)
          .join(' ')
          .trim();
      if (query.isEmpty) return const [];

      final uri =
          Uri.parse('$_baseUrl/search').replace(queryParameters: {'q': query});
      final result = await _fetchJson(client, uri);
      if (result == null || result is! List) return const [];

      return result
          .whereType<Map>()
          .map((item) => LrclibLyrics.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (e) {
      debugPrint('LrcLib: searchResults error: $e');
      return const [];
    } finally {
      client?.close(force: true);
    }
  }
}

class LrclibLyrics {
  final int? id;
  final String? trackName;
  final String? artistName;
  final String? albumName;
  final int? durationSeconds;
  final String? syncedLyrics;
  final String? plainLyrics;

  const LrclibLyrics({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.durationSeconds,
    required this.syncedLyrics,
    required this.plainLyrics,
  });

  bool get hasLyrics =>
      (syncedLyrics != null && syncedLyrics!.trim().isNotEmpty) ||
      (plainLyrics != null && plainLyrics!.trim().isNotEmpty);

  bool get hasSyncedLyrics =>
      syncedLyrics != null && syncedLyrics!.trim().isNotEmpty;

  bool get hasPlainLyrics =>
      plainLyrics != null && plainLyrics!.trim().isNotEmpty;

  factory LrclibLyrics.fromJson(Map<String, dynamic> json) {
    return LrclibLyrics(
      id: (json['id'] as num?)?.toInt(),
      trackName: json['trackName']?.toString(),
      artistName: json['artistName']?.toString(),
      albumName: json['albumName']?.toString(),
      durationSeconds: (json['duration'] as num?)?.round(),
      syncedLyrics: json['syncedLyrics']?.toString(),
      plainLyrics: json['plainLyrics']?.toString(),
    );
  }
}
