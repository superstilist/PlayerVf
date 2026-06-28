import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:player_vf/models/lyrics_model.dart';
import 'package:player_vf/utils/lyrics_parser.dart';

class LrcLibService {
  static const String _baseUrl = 'https://lrclib.net/api';
  
  // Simple in-memory cache for the session
  static final Map<String, LyricsDocument> _cache = {};

  /// Fetches lyrics from LRCLIB. Attempts to find synced lyrics first.
  static Future<LyricsDocument?> fetchLyrics({
    required String trackName,
    required String artistName,
    String? albumName,
    int? durationSeconds,
  }) async {
    final cacheKey = '$trackName|$artistName|$albumName|$durationSeconds';
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final uri = Uri.parse('$_baseUrl/get').replace(queryParameters: {
        'track_name': trackName,
        'artist_name': artistName,
        if (albumName != null && albumName.isNotEmpty) 'album_name': albumName,
        if (durationSeconds != null && durationSeconds > 0) 'duration': durationSeconds.toString(),
      });

      final response = await http.get(uri, headers: {
        'User-Agent': 'PlayerVF/1.0.0 (https://github.com/superstilist/PlayerVf)'
      });

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final syncedLyrics = data['syncedLyrics'] as String?;
        final plainLyrics = data['plainLyrics'] as String?;

        if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
          final doc = LyricsParser.parse(syncedLyrics, source: 'LRCLIB (Synced)');
          _cache[cacheKey] = doc;
          return doc;
        } else if (plainLyrics != null && plainLyrics.isNotEmpty) {
          final doc = LyricsParser.parse(plainLyrics, source: 'LRCLIB (Plain Text)');
          _cache[cacheKey] = doc;
          return doc;
        }
      } else if (response.statusCode == 404) {
        // Not found, try a broader search
        return _searchLyrics(trackName: trackName, artistName: artistName);
      }
    } catch (e) {
      print('LRCLIB fetch error: $e');
    }
    
    return null;
  }

  static Future<LyricsDocument?> _searchLyrics({
    required String trackName,
    required String artistName,
  }) async {
    try {
      final query = '$trackName $artistName'.trim();
      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: {'q': query});
      
      final response = await http.get(uri, headers: {
        'User-Agent': 'PlayerVF/1.0.0 (https://github.com/superstilist/PlayerVf)'
      });

      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);
        if (results.isNotEmpty) {
          // Find the first result that has synced lyrics
          for (final result in results) {
            final syncedLyrics = result['syncedLyrics'] as String?;
            if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
              return LyricsParser.parse(syncedLyrics, source: 'LRCLIB (Search Synced)');
            }
          }
          // If none have synced lyrics, take the first plain text
          final plainLyrics = results.first['plainLyrics'] as String?;
          if (plainLyrics != null && plainLyrics.isNotEmpty) {
            return LyricsParser.parse(plainLyrics, source: 'LRCLIB (Search Plain)');
          }
        }
      }
    } catch (e) {
      print('LRCLIB search error: $e');
    }
    return null;
  }
}
